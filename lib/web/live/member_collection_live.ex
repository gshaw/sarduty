defmodule Web.MemberCollectionLive do
  @moduledoc """
  Members, drawn by its report (#784): the tiles, search, filters, sorts, and pages are
  the clauses in `App.Report.Lists.members/0`, run by `App.Report.page/5`. A member runs
  it as a member, so team admins' own filters and the Away tile drop out (#440). The
  cells, Add member, Add to group, and Save as report stay here.
  """
  # A member gets the list but not the group form: "select" and "set-group" are not in
  # view_events (#547).
  use Web, {:live_view_app_layout, access: :team, view_events: ["change"]}

  import Web.Components.ActionBar, only: [action_bar: 1]
  import Web.Components.ReportPage

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Operation.SetGroupMembers
  alias App.Report
  alias App.Report.Error
  alias App.Report.Lists
  alias App.ViewData.ReportRecords
  alias Web.Components.ReportPage
  alias Web.MemberCollectionLive.GroupChoice

  def mount(_params, _session, socket) do
    groups = groups(socket.assigns)

    socket =
      socket
      |> assign(:page_title, "Members")
      |> assign(groups: groups, group_form?: groups != [], not_changed: nil)
      |> assign(choice: nil, group_id: nil, group_member_ids: MapSet.new())

    {:ok, socket}
  end

  # Only groups without rules: rules decide who is in the rest. Each with its label and
  # whether it is the team's Retiring group, by id.
  defp groups(%{team_admin?: true, current_team: team}) do
    organization_name = Team.organization_name(team) || "Your organization"

    for group <- Group.get_kept_by_hand(team.id) do
      %{
        id: group.id,
        title: Group.label(group, organization_name),
        retiring?: group.d4h_group_id == team.retiring_d4h_group_id
      }
    end
  end

  defp groups(_assigns), do: []

  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:given, Map.drop(params, ["subdomain"]))
      |> assign(:not_changed, nil)
      |> assign_list()

    {:noreply, socket}
  end

  defp assign_list(socket) do
    %{current_team: team, team_admin?: team_admin?, given: given} = socket.assigns
    now = DateTime.utc_now()

    case Report.page(Lists.members().query, team, given, now, team_admin?: team_admin?) do
      {:ok, view} ->
        view = without_tiles(view, team)
        rows = rows(view, team, team_admin?, now)
        attended = picked(view, "attended")

        socket
        |> assign(view: view, rows: rows, now: now, selected: MapSet.new())
        |> assign(attended: attended)
        |> assign(:clock, clock(rows, attended, team, Service.Period.today(now, team.timezone)))
        |> assign_paths(view, team)

      # The list's own text failing is a bug, not a bad URL; a test runs it.
      {:error, error} ->
        raise "Members' report: #{Error.text(error)}"
    end
  end

  defp assign_paths(socket, view, team) do
    assign(socket,
      form: ReportPage.controls_form(view),
      path_fn: &ReportPage.path(view, ~p"/teams/#{team}/members", &1),
      save_path: ~p"/teams/#{team}/reports/new?#{Map.put(view.params, "list", "members")}",
      csv_path: ~p"/teams/#{team}/reports/members/csv?#{Map.delete(view.params, "page")}"
    )
  end

  # No All tile: Not retired and Retired add up to it (#469), and All shows as the
  # Standing menu. No Retiring tile either: retiring members are under Retired, since
  # they no longer count as members, and the menu keeps Retiring for a team with a
  # Retiring group (#514).
  defp without_tiles(%{switch: switch} = view, team) do
    retiring? = Team.retiring?(team)
    tiles = Enum.reject(switch.tiles, &(&1.value in ["all", "retiring"]))
    options = Enum.filter(switch.options, &(elem(&1, 1) != "retiring" or retiring?))
    %{view | switch: %{switch | tiles: tiles, options: options}}
  end

  # The rows hold the members' ids and the columns' values; the cells read the members,
  # each standing as the viewer sees it.
  defp rows(view, team, team_admin?, now) do
    records = ReportRecords.load(view.result, team, now)
    members = Map.get(records, :member, %{})

    for [id, _ref_id, _position, last_attended, count, minutes | _] <- view.result.rows do
      %{
        member: Map.fetch!(members, id),
        standing: records.standings |> Map.get(id) |> Standing.visible(team_admin?),
        last_attended_at: last_attended,
        activity_count: count,
        total_minutes: minutes
      }
    end
  end

  def render(assigns) do
    assigns =
      assign(assigns, standing: assigns.view.switch.picked, change: change(assigns))

    ~H"""
    <.heading_row>
      <h1 class="title">{@page_title}</h1>
      <:action>
        <.button
          :if={@team_admin? and D4H.records?(@current_team)}
          id="member-add"
          navigate={~p"/teams/#{@current_team}/members/new"}
        >
          Add member
        </.button>
      </:action>
    </.heading_row>

    <.report_page
      id="member"
      view={@view}
      records={%{}}
      team={@current_team}
      now={nil}
      path_fn={@path_fn}
      form={@form}
      save_path={@team_admin? && @save_path}
      csv_path={@team_admin? && @csv_path}
      combobox={["group"]}
    >
      <:table>
        <p :if={@attended not in [nil, "all"]} id="attended-hint" class="hint">
          Attended counts from the latest of a member's last activity, the day they joined,
          the end of an away period, and a check-in.
        </p>

        <.banner
          :if={@not_changed}
          kind={:danger}
          title={@not_changed.title}
          id="group-not-changed"
          class="mb-4"
        >
          <ul>
            <li :for={{member, text} <- @not_changed.failed} id={"not-changed-#{member.id}"}>
              {member.name}: {text}
            </li>
          </ul>
        </.banner>

        <%!-- Team admins only: the table, the choices, and the bar in one form, so the bar
        sticks while the table scrolls. The filter bar's form sits outside this slot. --%>
        <.form
          :if={@group_form? and @rows != []}
          for={%{}}
          id="member-group-form"
          phx-change="select"
          phx-submit="set-group"
        >
          <.member_table
            rows={@rows}
            clock={@clock}
            view={@view}
            path_fn={@path_fn}
            team={@current_team}
            now={@now}
            group_form?={true}
            selected={@selected}
            retired?={retired?(@standing)}
          />
          <.group_choices
            choice={@choice}
            group_id={@group_id}
            groups={@groups}
            options={@change.options}
          />
          <.action_bar id="member-bar" hint={@change.hint}>
            <.button
              id="member-change-send"
              variant={:primary}
              disabled={@change.count == 0}
              phx-disable-with={if @change.action == :remove, do: "Removing…", else: "Adding…"}
              {@change.confirm}
            >
              {@change.button}
            </.button>
          </.action_bar>
        </.form>

        <.member_table
          :if={!@group_form? or @rows == []}
          rows={@rows}
          clock={@clock}
          view={@view}
          path_fn={@path_fn}
          team={@current_team}
          now={@now}
          group_form?={false}
          selected={@selected}
          retired?={retired?(@standing)}
        />

        <.empty_state
          :if={@rows == [] and @view.q != ""}
          id="no-matching-members"
          title="No members match"
        >
          Change the search or the filters.
          <:action :if={@standing != "all"}>
            <.a patch={@path_fn.(standing: "all", page: nil)}>Search all members</.a>
          </:action>
        </.empty_state>
      </:table>
    </.report_page>
    """
  end

  # The checked members, the picked choice and group, and what the bar's button does
  # with them: its words, its count, its confirm, and why it waits.
  defp change(%{group_form?: false}), do: nil

  defp change(assigns) do
    checked = checked(assigns.rows, assigns.selected)
    group = group(assigns.groups, assigns.group_id, assigns.group_member_ids)
    action = action(assigns.choice)
    changes = if action, do: GroupChoice.changes(action, checked, group), else: []
    service = D4H.service_name(assigns.current_team)

    %{
      action: action,
      count: length(changes),
      hint: bar_hint(action, checked, group),
      button:
        if(action,
          do: GroupChoice.button_text(action, length(changes), group),
          else: "Change members"
        ),
      confirm: if(action, do: GroupChoice.confirm(action, changes, group, service), else: %{}),
      options:
        for(
          a <- [:add, :remove],
          do: {GroupChoice.label(a), Atom.to_string(a), GroupChoice.hint(a, checked, group)}
        )
    }
  end

  attr :choice, :string, required: true, doc: ~s("add", "remove", or nil)
  attr :group_id, :integer, required: true
  attr :groups, :list, required: true
  attr :options, :list, required: true, doc: "each choice with its hint"

  # For the checked members (#920's list): Add to group and Remove from group, with the
  # Group box beside the picked one. Nothing is picked at the start. Neither choice greys
  # out: another group could reach someone, so the bar's button greys instead, with why.
  defp group_choices(assigns) do
    ~H"""
    <div id="member-change" class="mt-8">
      <.input
        type="radios"
        id="member-change-choice"
        name="change"
        label="For the checked members"
        value={@choice}
        options={@options}
      >
        <:beside :if={@choice} value={@choice}>
          <.combobox
            id="member-group-id"
            name="group_id"
            value={@group_id}
            options={for g <- @groups, do: {g.title, g.id}}
            prompt="Select a group"
            placeholder="Select a group"
            aria-label="Group"
          />
        </:beside>
      </.input>
    </div>
    """
  end

  defp action("add"), do: :add
  defp action("remove"), do: :remove
  defp action(_choice), do: nil

  # What to do next while the button is greyed.
  defp bar_hint(_action, [], _group), do: "Check members, then select what to do."
  defp bar_hint(nil, _checked, _group), do: "Select what to do."
  defp bar_hint(action, checked, group), do: GroupChoice.waiting(action, checked, group)

  defp checked(rows, selected),
    do: for(%{member: m} <- rows, MapSet.member?(selected, m.id), do: m)

  defp group(groups, group_id, member_ids) do
    case Enum.find(groups, &(&1.id == group_id)) do
      nil -> nil
      group -> %{title: group.title, retiring?: group.retiring?, member_ids: member_ids}
    end
  end

  attr :rows, :list, required: true
  attr :clock, :map, required: true, doc: "where each member's clock starts, by id, or %{}"
  attr :view, App.Report.View, required: true
  attr :path_fn, :any, required: true
  attr :team, :any, required: true
  attr :now, :any, required: true
  attr :group_form?, :boolean, required: true, doc: "tick boxes for Add to group"
  attr :selected, :any, required: true
  attr :retired?, :boolean, required: true

  defp member_table(assigns) do
    ~H"""
    <.table
      id="member_collection"
      rows={@rows}
      sort={@view.sort}
      path_fn={@path_fn}
      class="table-striped"
    >
      <:col :let={row} :if={@group_form?} label="" class="w-px" select_all>
        <input
          type="checkbox"
          id={"select-#{row.member.id}"}
          name="member_ids[]"
          value={row.member.id}
          checked={MapSet.member?(@selected, row.member.id)}
          aria-label={row.member.name}
        />
      </:col>
      <:col :let={row} label="ID" class="w-px max-md:hidden" sorts={[{"↑", "id"}]}>
        {row.member.ref_id}
      </:col>
      <:col :let={row} label="Member" sorts={[{"↑", "name"}]}>
        <.member_cell
          id={"standing-#{row.member.id}"}
          member={row.member}
          team={@team}
          standing={unless_tile(row.standing, @view.switch.picked)}
          path={~p"/teams/#{@team}/members/#{row.member.id}"}
        />
      </:col>
      <:col :let={row} label="Role" sorts={[{"↑", "role"}]}>
        {row.member.position}
      </:col>
      <:col
        :let={row}
        label="Last attended"
        class="w-px whitespace-nowrap"
        sorts={[{"↑", "attended"}, {"↓", "attended-"}]}
      >
        <.last_attended_cell
          id={"last-attended-#{row.member.id}"}
          value={row.last_attended_at}
          now={@now}
          timezone={@team.timezone}
        />
        <div
          :if={@clock[row.member.id]}
          id={"clock-starts-#{row.member.id}"}
          class="text-text-muted"
        >
          {@clock[row.member.id]}
        </div>
      </:col>
      <:col
        :let={row}
        label="Activities"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "activities-"}, {"↑", "activities"}]}
      >
        {row.activity_count}
      </:col>
      <:col
        :let={row}
        label="Hours"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "duration-"}, {"↑", "duration"}]}
      >
        <.hours_cell minutes={row.total_minutes} />
      </:col>
      <:col
        :let={row}
        label="Joined"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "date-"}, {"↑", "date"}]}
      >
        <.date_cell value={row.member.joined_at} timezone={@team.timezone} />
      </:col>
      <:col
        :let={row}
        :if={@retired?}
        label="Retired"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "retired-"}, {"↑", "retired"}]}
      >
        <.date_cell value={row.member.left_at} timezone={@team.timezone} />
      </:col>
    </.table>
    """
  end

  defp picked(view, name), do: Enum.find_value(view.filters, &(&1.name == name && &1.picked))

  defp retired?(standing), do: standing == "all" or "retired" in String.split(standing, ",")

  # A tile that names one standing, such as Retired, says it for every row: no badge.
  # Away keeps its badge, since each row's last day differs.
  defp unless_tile({:away, _period} = away, _picked), do: away

  defp unless_tile(standing, picked),
    do: if(Atom.to_string(standing) == picked, do: :active, else: standing)

  # With Attended on, where each member's clock starts, when it's somewhere other than
  # the last activity, which the cell already shows.
  defp clock(_rows, attended, _team, _today) when attended in [nil, "all"], do: %{}

  defp clock(rows, _attended, team, today) do
    parts = Member.clock_parts(team, Enum.map(rows, & &1.member.id), today)

    for row <- rows,
        {why, date} <- [
          row |> Map.merge(parts[row.member.id]) |> Member.clock_start(team.timezone)
        ],
        why != :attended,
        into: %{},
        do: {row.member.id, "#{clock_why(why)} #{Service.Format.day_in_year(date, today)}"}
  end

  defp clock_why(:checked_in), do: "Checked in"
  defp clock_why(:back), do: "Back from leave"
  defp clock_why(:joined), do: "Joined"

  def handle_event("change", %{"values" => values}, socket) do
    path = socket.assigns.path_fn.([{:page, nil} | Map.to_list(values)])
    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  # A check, a choice, or a group. The Group box shows only beside a picked choice, so
  # without it the group stays as it was; a new group loads who is in it, once.
  def handle_event("select", params, socket) do
    group_id =
      if Map.has_key?(params, "group_id"),
        do: parse_id(params["group_id"]),
        else: socket.assigns.group_id

    socket =
      socket
      |> assign(selected: params |> ids() |> MapSet.new(), choice: params["change"])
      |> assign_group(group_id)

    {:noreply, socket}
  end

  # The ticked rows of this page. The ids come from the browser; SetGroupMembers looks
  # each one up through the team.
  def handle_event("set-group", %{"change" => action} = params, socket)
      when action in ["add", "remove"] do
    %{current_team: team, current_user: user} = socket.assigns
    action = Map.fetch!(%{"add" => :add, "remove" => :remove}, action)
    group_id = parse_id(params["group_id"])

    case SetGroupMembers.call(team, action, group_id, ids(params), user, DateTime.utc_now()) do
      {:ok, result} ->
        socket =
          socket
          |> assign_list()
          |> assign(:group_id, nil)
          |> assign_group(group_id)
          |> assign(:not_changed, not_changed(action, result))

        {:noreply, put_result_flash(socket, action, result)}

      {:error, text} ->
        {:noreply, socket |> assign(:group_id, group_id) |> put_flash(:error, text)}
    end
  end

  # Sent with nothing picked, as only a browser's own submit can.
  def handle_event("set-group", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Select what to do.")}

  defp count_members(n), do: Service.Format.count(n, one: "%d member", many: "%d members")

  defp put_result_flash(socket, _action, %{done: [], skipped: []}), do: clear_flash(socket)

  defp put_result_flash(socket, action, %{group: group, done: done, skipped: skipped}) do
    {verb, skip} =
      case action do
        :add -> {"added to", "in #{group.title} already"}
        :remove -> {"removed from", "not in #{group.title}"}
      end

    text =
      "#{count_members(length(done))} #{verb} #{group.title}." <>
        if skipped == [],
          do: "",
          else:
            " #{Service.Format.count(length(skipped), one: "%d was", many: "%d were")} #{skip}."

    put_flash(socket, :info, text)
  end

  defp not_changed(_action, %{failed: []}), do: nil

  defp not_changed(action, %{group: group, failed: failed}) do
    verb = if action == :add, do: "added to", else: "removed from"
    %{title: "#{count_members(length(failed))} not #{verb} #{group.title}", failed: failed}
  end

  defp assign_group(%{assigns: %{group_id: group_id}} = socket, group_id), do: socket

  defp assign_group(socket, group_id) do
    ids = GroupMember.member_ids(socket.assigns.current_team.id, group_id) || MapSet.new()
    assign(socket, group_id: group_id, group_member_ids: ids)
  end

  defp ids(params) do
    params
    |> Map.get("member_ids", [])
    |> List.wrap()
    |> Enum.map(&parse_id/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_id(_id), do: nil
end
