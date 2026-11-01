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

  import Web.Components.ReportPage

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.Member
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Operation.SetGroupMembers
  alias App.Report
  alias App.Report.Error
  alias App.Report.Lists
  alias App.ViewData.ReportRecords
  alias Web.Components.ReportPage

  def mount(_params, _session, socket) do
    groups = groups(socket.assigns)

    socket =
      socket
      |> assign(:page_title, "Members")
      |> assign(groups: groups, group_form?: groups != [], group_id: nil, not_changed: nil)

    {:ok, socket}
  end

  # Only groups without rules: rules decide who is in the rest.
  defp groups(%{team_admin?: true, current_team: team}) do
    organization_name = Team.organization_name(team) || "Your organization"

    for group <- Group.get_kept_by_hand(team.id),
        do: {Group.label(group, organization_name), group.id}
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
        |> assign(attended: attended, details: picked(view, "details"))
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
      save_path: ~p"/teams/#{team}/reports/new?#{Map.put(view.params, "list", "members")}"
    )
  end

  # No All tile: Not retired and Retired add up to it (#469), and All shows as the
  # Standing menu. Retiring only for a team with a Retiring group (#514).
  defp without_tiles(%{switch: switch} = view, team) do
    retiring? = Team.retiring?(team)
    keep? = fn value -> value != "retiring" or retiring? end
    tiles = Enum.filter(switch.tiles, &(&1.value != "all" and keep?.(&1.value)))
    options = Enum.filter(switch.options, &keep?.(elem(&1, 1)))
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
    assigns = assign(assigns, :standing, assigns.view.switch.picked)

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
        <.button :if={@team_admin?} id="member-save-report" navigate={@save_path}>
          Save as report
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
      combobox={["group", "activity_tag"]}
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

        <%!-- Team admins only. Apart from the filter bar's form, as forms cannot nest; the
        tick boxes join it with their form attribute. --%>
        <.form
          :if={@group_form? and @rows != []}
          for={%{}}
          id="member-group-form"
          phx-change="select"
          phx-submit="set-group"
          class="table-actions"
        >
          <.combobox
            id="member-group-id"
            name="group_id"
            value={@group_id}
            options={@groups}
            aria-label="Group"
          />
          <.button id="member-group-add" name="do" value="add" phx-disable-with="Adding…">
            Add to group
          </.button>
          <.button
            id="member-group-remove"
            name="do"
            value="remove"
            phx-disable-with="Removing…"
            data-confirm={remove_confirm(@selected, @rows, @group_id, @groups)}
          >
            Remove from group
          </.button>
        </.form>

        <.member_table
          rows={@rows}
          clock={@clock}
          view={@view}
          path_fn={@path_fn}
          team={@current_team}
          now={@now}
          group_form?={@group_form?}
          selected={@selected}
          details={@details}
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

  attr :rows, :list, required: true
  attr :clock, :map, required: true, doc: "where each member's clock starts, by id, or %{}"
  attr :view, App.Report.View, required: true
  attr :path_fn, :any, required: true
  attr :team, :any, required: true
  attr :now, :any, required: true
  attr :group_form?, :boolean, required: true, doc: "tick boxes for Add to group"
  attr :selected, :any, required: true
  attr :details, :string, required: true, doc: "the Details filter's pick"
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
          form="member-group-form"
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
          path={member_path(@team, row.member, @view)}
        />
      </:col>
      <:col :let={row} label="Role" sorts={[{"↑", "role"}]}>
        {row.member.position}
      </:col>
      <:col :let={row} :if={@details == "missing"} label="Missing">
        <span id={"missing-#{row.member.id}"}>{missing_text(row.member)}</span>
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

  # With a tag on, the member's page opens on the activities that were counted.
  defp member_path(team, member, view) do
    case picked(view, "activity_tag") do
      tag when tag in [nil, "all"] ->
        ~p"/teams/#{team}/members/#{member.id}"

      tag ->
        ~p"/teams/#{team}/members/#{member.id}?#{[when: picked(view, "when") || "all", activity_tag: tag]}"
    end
  end

  defp missing_text(member) do
    member
    |> Member.missing_details()
    |> Enum.map_join(", ", &missing_label/1)
  end

  defp missing_label(:mobile_phone), do: "Mobile phone"
  defp missing_label(:email), do: "Email"
  defp missing_label(:address), do: "Address"

  def handle_event("change", %{"values" => values}, socket) do
    path = socket.assigns.path_fn.([{:page, nil} | Map.to_list(values)])
    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  def handle_event("select", params, socket) do
    selected = params |> ids() |> MapSet.new()
    {:noreply, assign(socket, selected: selected, group_id: parse_id(params["group_id"]))}
  end

  # The ticked rows of this page. The ids come from the browser; SetGroupMembers looks
  # each one up through the team.
  def handle_event("set-group", %{"do" => action} = params, socket)
      when action in ["add", "remove"] do
    %{current_team: team, current_user: user} = socket.assigns
    action = Map.fetch!(%{"add" => :add, "remove" => :remove}, action)
    group_id = parse_id(params["group_id"])

    case SetGroupMembers.call(team, action, group_id, ids(params), user, DateTime.utc_now()) do
      {:ok, result} ->
        socket =
          socket
          |> assign_list()
          |> assign(:group_id, group_id)
          |> assign(:not_changed, not_changed(action, result))

        {:noreply, put_result_flash(socket, action, result)}

      {:error, text} ->
        {:noreply, socket |> assign(:group_id, group_id) |> put_flash(:error, text)}
    end
  end

  # No confirm without a group and ticks: the click gets "Select a group" or "Select
  # members" instead.
  defp remove_confirm(selected, rows, group_id, groups) do
    group = Enum.find_value(groups, fn {label, id} -> id == group_id && label end)
    names = for %{member: m} <- rows, MapSet.member?(selected, m.id), do: m.name

    cond do
      is_nil(group) or names == [] -> nil
      length(names) <= 5 -> "Remove #{Service.Format.and_list(names)} from #{group}?"
      true -> "Remove #{count_members(length(names))} from #{group}?"
    end
  end

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
