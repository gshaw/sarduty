defmodule Web.MemberCollectionLive do
  # A member gets the list but not the group form: "select" and "set-group" are not in
  # view_events (#547).
  use Web, {:live_view_app_layout, access: :team, view_events: ["change"]}

  import Web.Components.FilterBar
  import Web.Components.StatSwitch

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Operation.SetGroupMembers
  alias App.ViewModel.MemberFilterViewModel

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
    case MemberFilterViewModel.validate(params, socket.assigns.team_admin?) do
      {:ok, filter_options, changeset} ->
        socket =
          socket
          |> assign(:form, to_form(changeset, as: "form"))
          |> assign(:not_changed, nil)
          |> assign_list(filter_options)

        {:noreply, socket}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  defp assign_list(socket, filter_options) do
    %{current_team: current_team, team_admin?: team_admin?} = socket.assigns
    now = DateTime.utc_now()
    today = Service.Period.today(now, current_team.timezone)
    retiring? = Team.retiring?(current_team)

    tile? =
      MemberFilterViewModel.switch_standing?(filter_options.standing, team_admin?, retiring?)

    socket
    |> assign(Map.take(filter_options, [:sort, :details, :attended]))
    |> assign(filter_options: filter_options, now: now, today: today, retiring?: retiring?)
    |> assign(:standing?, standing_column?(current_team, team_admin?, today, now))
    |> assign(:retired?, MemberFilterViewModel.shows_retired?(filter_options.standing))
    |> assign(:standing_tile?, tile?)
    |> assign(:paginated, build_paginated_content(current_team, filter_options))
    |> assign(
      :standing_counts,
      MemberFilterViewModel.standing_counts(current_team, filter_options, team_admin?, now)
    )
    |> assign(:path_fn, build_path_fn(current_team, filter_options))
    |> assign(:selected, MapSet.new())
  end

  def render(assigns) do
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
    <.stat_switch id="member-switch" label="Standing">
      <:view
        :for={{label, standing} <- MemberFilterViewModel.standing_switch(@team_admin?, @retiring?)}
        id={"member-view-#{standing}"}
        patch={@path_fn.(standing: standing, page: nil)}
        current={@filter_options.standing == standing}
        count={@standing_counts[standing]}
      >
        {label}
      </:view>
    </.stat_switch>
    <.filter_bar
      for={@form}
      id="member_filter_form"
      count={Service.Format.count(@paginated.total_entries, one: "%d member", many: "%d members")}
      repeats={@paginated.total_entries == @standing_counts[@filter_options.standing]}
      clear={@path_fn.(:reset)}
      path_fn={@path_fn}
      page={@paginated}
      hidden={[@form[:sort]] ++ if(@standing_tile?, do: [@form[:standing]], else: [])}
    >
      <:search field={@form[:q]} />
      <:filter
        :if={!@standing_tile?}
        field={@form[:standing]}
        label="Standing"
        options={
          MemberFilterViewModel.standing_kinds(
            @form[:standing].value,
            @team_admin?,
            @retiring?
          )
        }
        default="current"
      />
      <:filter
        field={@form[:when]}
        label="Period"
        options={MemberFilterViewModel.when_kinds(@current_team)}
        default={MemberFilterViewModel.current_year()}
      />
      <:filter
        field={@form[:group]}
        label="Group"
        type="combobox"
        options={MemberFilterViewModel.group_kinds(@current_team)}
        default=""
      />
      <:filter
        field={@form[:activity_tag]}
        label="Tag"
        type="combobox"
        more
        options={MemberFilterViewModel.activity_tag_kinds(@current_team)}
        default=""
      />
      <%!-- Team admins' own lists: missing details, and check-ins and away periods (#440). --%>
      <:filter
        :if={@team_admin?}
        field={@form[:details]}
        label="Details"
        more
        options={MemberFilterViewModel.details_kinds()}
        default="all"
      />
      <:filter
        :if={@team_admin?}
        field={@form[:attended]}
        label="Attended"
        more
        options={MemberFilterViewModel.attended_kinds()}
        default="all"
      />
      <:filter
        :if={@team_admin?}
        field={@form[:items]}
        label="Items"
        more
        options={MemberFilterViewModel.items_kinds()}
        default="all"
      />
      <:filter
        :if={@team_admin?}
        field={@form[:access]}
        label="Access"
        more
        options={MemberFilterViewModel.access_kinds(D4H.service_name(@current_team))}
        default="all"
      />
    </.filter_bar>
    <p :if={@attended not in [nil, "all"]} id="attended-hint" class="hint">
      Attended counts from the latest of a member's last activity, the day they joined, the
      end of an away period, and a check-in.
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
      :if={@group_form? and @paginated.entries != []}
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
        data-confirm={remove_confirm(@selected, @paginated.entries, @group_id, @groups)}
      >
        Remove from group
      </.button>
    </.form>
    <.table
      id="member_collection"
      rows={@paginated.entries}
      sort={@sort}
      path_fn={@path_fn}
      class="table-striped"
    >
      <:col :let={record} :if={@group_form?} label="" class="w-px" select_all>
        <input
          type="checkbox"
          id={"select-#{record.member.id}"}
          name="member_ids[]"
          form="member-group-form"
          value={record.member.id}
          checked={MapSet.member?(@selected, record.member.id)}
          aria-label={record.member.name}
        />
      </:col>
      <:col :let={record} label="ID" class="w-px max-md:hidden" sorts={[{"↑", "id"}]}>
        {record.member.ref_id}
      </:col>
      <:col :let={record} label="Member" sorts={[{"↑", "name"}]}>
        <.member_cell
          member={record.member}
          team={@current_team}
          standing={standing(record, @team_admin?, @today, @now)}
          path={member_path(@current_team, record.member, @filter_options)}
        />
      </:col>
      <:col :let={record} label="Role" sorts={[{"↑", "role"}]}>
        {record.member.position}
      </:col>
      <:col
        :let={record}
        :if={@standing?}
        label="Standing"
        class="whitespace-nowrap"
        sorts={if @team_admin?, do: [{"↑", "standing"}, {"↓", "standing-"}]}
      >
        <span id={"standing-#{record.member.id}"}>{standing_text(record, @team_admin?, @today, @now)}</span>
      </:col>
      <:col :let={record} :if={@details == "missing"} label="Missing">
        <span id={"missing-#{record.member.id}"}>{missing_text(record.member)}</span>
      </:col>
      <:col
        :let={record}
        label="Last attended"
        class="w-px whitespace-nowrap"
        sorts={[{"↑", "attended"}, {"↓", "attended-"}]}
      >
        <.last_attended_cell
          id={"last-attended-#{record.member.id}"}
          value={record.last_attended_at}
          now={@now}
          timezone={@current_team.timezone}
        />
        <div
          :if={@attended not in [nil, "all"] and clock_why(record, @current_team)}
          id={"clock-starts-#{record.member.id}"}
          class="text-text-muted"
        >
          {clock_starts(record, @current_team, @today)}
        </div>
      </:col>
      <:col
        :let={record}
        label="Activities"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "activities-"}, {"↑", "activities"}]}
      >
        {record.activity_count}
      </:col>
      <:col
        :let={record}
        label="Hours"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "duration-"}, {"↑", "duration"}]}
      >
        <.hours_cell minutes={record.total_minutes} />
      </:col>
      <:col
        :let={record}
        label="Joined"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "date-"}, {"↑", "date"}]}
      >
        <.date_cell value={record.member.joined_at} timezone={@current_team.timezone} />
      </:col>
      <:col
        :let={record}
        :if={@retired?}
        label="Retired"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "retired-"}, {"↑", "retired"}]}
      >
        <.date_cell value={record.member.left_at} timezone={@current_team.timezone} />
      </:col>
    </.table>

    <.empty_state
      :if={@paginated.entries == [] and @filter_options.q not in [nil, ""]}
      id="no-matching-members"
      title="No members match"
    >
      Change the search or the filters.
      <:action :if={@filter_options.standing != "all"}>
        <.a patch={@path_fn.(standing: "all", page: nil)}>Search all members</.a>
      </:action>
    </.empty_state>

    <.pagination class="my-4" paginated={@paginated} path_fn={@path_fn} />
    """
  end

  # Shown only when some current member is not active, whatever the filter shows. A member
  # never sees Away (#440), so their list shows it only for Retiring or Not a person:
  # Retired has its own column.
  defp standing_column?(team, team_admin?, today, now),
    do: Member.any_not_active?(team, today, now, team_admin?)

  # The row has the away period's last day only, which is all the column shows.
  defp standing(record, team_admin?, today, now) do
    away =
      if record.away_until,
        do: [%MemberAwayPeriod{starts_on: today, ends_on: record.away_until}],
        else: []

    record.member
    |> Standing.of(away, record.retiring?, today, now)
    |> Standing.visible(team_admin?)
  end

  defp standing_text(record, team_admin?, today, now) do
    case standing(record, team_admin?, today, now) do
      {:away, period} -> "Away until #{Service.Format.day_in_year(period.ends_on, today)}"
      standing -> Standing.text(standing)
    end
  end

  # Only when the clock starts somewhere other than the last activity, which the cell
  # already shows.
  defp clock_why(record, team) do
    case Member.clock_start(record, team.timezone) do
      {:attended, _date} -> nil
      {why, _date} -> why
      nil -> nil
    end
  end

  defp clock_starts(record, team, today) do
    {why, date} = Member.clock_start(record, team.timezone)
    "#{clock_why(why)} #{Service.Format.day_in_year(date, today)}"
  end

  defp clock_why(:attended), do: "Last attended"
  defp clock_why(:checked_in), do: "Checked in"
  defp clock_why(:back), do: "Back from leave"
  defp clock_why(:joined), do: "Joined"

  # With a tag on, the member's page opens on the activities that were counted.
  defp member_path(team, member, %{activity_tag: tag} = filter_options)
       when tag not in [nil, ""],
       do:
         ~p"/teams/#{team}/members/#{member.id}?#{[when: filter_options.when || "all", activity_tag: tag]}"

  defp member_path(team, member, _filter_options), do: ~p"/teams/#{team}/members/#{member.id}"

  defp missing_text(member) do
    member
    |> Member.missing_details()
    |> Enum.map_join(", ", &missing_label/1)
  end

  defp missing_label(:mobile_phone), do: "Mobile phone"
  defp missing_label(:email), do: "Email"
  defp missing_label(:address), do: "Address"

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
          |> assign(:group_id, group_id)
          |> assign(:not_changed, not_changed(action, result))
          |> assign_list(socket.assigns.filter_options)

        {:noreply, put_result_flash(socket, action, result)}

      {:error, text} ->
        {:noreply, socket |> assign(:group_id, group_id) |> put_flash(:error, text)}
    end
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    case MemberFilterViewModel.validate(form_params, socket.assigns.team_admin?) do
      {:ok, filter_options, _changeset} ->
        path = build_filter_path(socket.assigns.current_team, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  # No confirm without a group and ticks: the click gets "Select a group" or "Select
  # members" instead.
  defp remove_confirm(selected, entries, group_id, groups) do
    group = Enum.find_value(groups, fn {label, id} -> id == group_id && label end)
    names = for %{member: m} <- entries, MapSet.member?(selected, m.id), do: m.name

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

  def build_paginated_content(team, filter_options) do
    MemberFilterViewModel.build_paginated_content(team, filter_options)
  end

  def build_path_fn(team, filter_options) do
    fn changed_options ->
      case changed_options do
        :reset ->
          build_filter_path(team, %MemberFilterViewModel{})

        _ ->
          build_filter_path(team, Map.merge(filter_options, Map.new(changed_options)))
      end
    end
  end

  def build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/teams/#{team}/members?#{query_params}"
  end
end
