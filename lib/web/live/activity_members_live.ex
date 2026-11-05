defmodule Web.ActivityMembersLive do
  @moduledoc """
  An activity's Members tab: who it invites and how they replied, and from the start its
  attendance (#766). Web.ActivityLive draws the page around it, as it does History; this
  module owns the tab: the members checked, the change picked, and which step is open.

  Before the start it's one table by reply, as #444 made it, with Add members, Remove
  members, Send reminders, and Send an update on pages of their own. From the start it's
  a table for each attendance, Attended, Absent, then No reply, last, next to the change,
  as Travel puts Not set. Everyone sees them. Team admins check members in them, from the
  start until the activity is published, and change them under the tables: one list and
  one button, as on Travel.

  A filter bar over the tables, before and after the start, shows one group's members
  (#895), in the URL as `?group=`. The ticks are the rows it shows: changing it unchecks
  the rows it hides, so a button never reaches someone off the screen. The tab's and the
  steps' paths keep it, so Back opens the tab as it was.

  Each change is a module in `@actions`, with Web.ActivityMembersLive.Action: its label,
  its hint, when it's offered, how it counts the button, and whether it applies in place
  or opens a step. A change in place calls its operation, and the tables, the panel's
  counts, and Travel's badge update at once; nothing stays checked. A step (#895) is a
  LiveComponent on a `live_action` route of this LiveView, such as `/members/remind`,
  drawn in the tab's place, so the ticks never leave the page:

  - The button patches to the step's route. Back patches to the tab, and the ticks are
    still there.
  - A step opened with nothing it changes, such as after a refresh, lands on the tab
    with a toast, since the ticks live only in this page.
  - The step sends `{:step_done, kind, text}` once it's done: the tab reloads, clears
    the ticks, and shows the toast.
  """
  # Everyone filters the tables: "change" is the filter bar's.
  use Web, {:live_view_app_layout, access: :team, view_events: ["change"]}

  import Web.Components.Columns, only: [member_cell: 1, hours_cell: 1]
  import Web.Components.FilterBar

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Reminder
  alias App.Operation.ChangeAttendance
  alias App.ViewData.ActivityMembers
  alias App.ViewModel.ActivityMembersFilterViewModel
  alias Service.Format
  alias Web.ActivityLive
  alias Web.ActivityMembersLive.Absent
  alias Web.ActivityMembersLive.Attended
  alias Web.ActivityMembersLive.Remove
  alias Web.Components.Reply

  @actions [Attended, Absent, Remove]

  @doc "Every change the tab offers, in the list's order."
  def actions, do: @actions

  def mount(params, session, socket) do
    {:ok, socket} = ActivityLive.mount(params, session, socket)

    {:ok,
     assign(socket,
       selected: MapSet.new(),
       choice: nil,
       step: nil,
       groups: Group.kinds(socket.assigns.current_team)
     )}
  end

  def handle_params(params, uri, socket) do
    {:noreply, socket} = ActivityLive.handle_params(params, uri, socket)

    {:noreply,
     socket |> assign_filter(params) |> keep_ticks() |> open_step(socket.assigns.live_action)}
  end

  # The filter bar's Group (#895), in the URL as `?group=`: the tables show only its members.
  defp assign_filter(socket, params) do
    %{current_team: team, groups: groups} = socket.assigns
    filter = ActivityMembersFilterViewModel.validate(params, groups)
    assign(socket, filter: filter, group_ids: GroupMember.member_ids(team.id, filter.group))
  end

  # Ticks only for the rows the tab shows: a member who went, or one the filter hides, so
  # the button never reaches someone off the screen.
  defp keep_ticks(socket) do
    ids = socket.assigns |> shown() |> MapSet.new(& &1.member.id)
    assign(socket, selected: MapSet.intersection(socket.assigns.selected, ids))
  end

  # The rows the filter shows.
  defp shown(%{members: members, group_ids: nil}), do: members

  defp shown(%{members: members, group_ids: ids}),
    do: Enum.filter(members, &MapSet.member?(ids, &1.member.id))

  defp open_step(socket, :members), do: assign(socket, step: nil)

  defp open_step(socket, live_action) do
    checked = checked(socket.assigns)
    action = socket.assigns |> offered() |> Enum.find(&(&1.run() == {:step, live_action}))

    if action && action.count(checked) > 0 do
      assign(socket, step: action, choice: action.value())
    else
      socket
      |> assign(step: nil)
      |> put_flash(:error, "Check the members again. Reloading the page clears them.")
      |> push_patch(to: tab_path(socket.assigns))
    end
  end

  # What the actions read: the activity, its team, and now.
  defp ctx(assigns),
    do: %{activity: assigns.activity, team: assigns.current_team, now: assigns.now}

  # The changes the list offers now: none for a member, or on a deleted activity.
  defp offered(%{team_admin?: true, activity: %Activity{deleted_at: nil}} = assigns),
    do: Enum.filter(@actions, & &1.offered?(ctx(assigns)))

  defp offered(_assigns), do: []

  defp checked(%{selected: selected} = assigns),
    do: assigns |> shown() |> Enum.filter(&MapSet.member?(selected, &1.member.id))

  defp chosen(%{choice: choice} = assigns),
    do: assigns |> offered() |> Enum.find(&(&1.value() == choice))

  # The filter bar: the tab again with the group in the URL, and keep_ticks unchecks the
  # rows it hides.
  def handle_event("change", %{"form" => form}, socket) do
    filter = ActivityMembersFilterViewModel.validate(form, socket.assigns.groups)
    %{current_team: team, activity: activity} = socket.assigns
    {:noreply, push_patch(socket, to: members_path(team, activity, filter))}
  end

  # The checked members and the change, kept so a re-render never unchecks them.
  def handle_event("tick", params, socket) do
    {:noreply,
     assign(socket,
       selected: params |> selected_ids() |> MapSet.new(),
       choice: params["change"]
     )}
  end

  def handle_event("apply", params, socket) do
    socket =
      assign(socket,
        selected: params |> selected_ids() |> MapSet.new(),
        choice: params["change"]
      )

    case chosen(socket.assigns) do
      nil -> {:noreply, put_flash(socket, :error, "Select a change for the checked members.")}
      action -> run(socket, action, action.run())
    end
  end

  def handle_event(event, params, socket), do: ActivityLive.handle_event(event, params, socket)

  # Each id with the status the tab showed for it, so the operation skips anyone whose
  # attendance changed since.
  defp run(socket, _action, {:in_place, change}) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns
    shown = for row <- checked(socket.assigns), do: {row.member.id, row.status}

    case ChangeAttendance.call(team, activity, shown, change, user, DateTime.utc_now()) do
      {:ok, result} ->
        kind = if result.not_changed == [], do: :info, else: :error
        {:noreply, done(socket, kind, ChangeAttendance.result_text(result))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, ChangeAttendance.error_text(team, reason))}
    end
  end

  defp run(socket, action, {:step, _live_action}) do
    count = socket.assigns |> checked() |> action.count()

    if count > 0,
      do: {:noreply, push_patch(socket, to: step_path(socket.assigns, action))},
      else: {:noreply, put_flash(socket, :error, "Check the members to change first.")}
  end

  # The tab again, from the copy the change wrote, with nothing checked.
  defp done(socket, kind, text) do
    socket
    |> assign(selected: MapSet.new(), choice: nil, now: DateTime.utc_now())
    |> ActivityLive.assign_people()
    |> put_flash(kind, text)
  end

  def handle_info({:step_done, kind, text}, socket),
    do: {:noreply, socket |> done(kind, text) |> push_patch(to: tab_path(socket.assigns))}

  def handle_info(message, socket), do: ActivityLive.handle_info(message, socket)

  defdelegate render(assigns), to: ActivityLive

  # The tab, and a step, keep the filter, so Back opens the tab as it was.
  defp tab_path(%{current_team: team, activity: activity, filter: filter}),
    do: members_path(team, activity, filter)

  defp members_path(team, activity, filter),
    do:
      ~p"/teams/#{team}/activities/#{activity.id}/members?#{ActivityMembersFilterViewModel.query_params(filter)}"

  defp step_path(%{current_team: team, activity: activity, filter: filter}, action) do
    {:step, live_action} = action.run()
    segment = live_action |> Atom.to_string() |> String.replace("_", "-")

    ~p"/teams/#{team}/activities/#{activity.id}/members/#{segment}?#{ActivityMembersFilterViewModel.query_params(filter)}"
  end

  # Ids come from the browser; only members the tab shows are changed.
  defp selected_ids(params) do
    params
    |> Map.get("member_ids", [])
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {id, ""} -> [id]
        _other -> []
      end
    end)
  end

  attr :activity, :map, required: true
  attr :team, :any, required: true
  attr :members, :list, required: true
  attr :standings, :map, required: true, doc: "each member's standing, by id"
  attr :started?, :boolean, required: true
  attr :now, :any, required: true
  attr :team_admin?, :boolean, default: false
  attr :reminded, :map, default: %{}, doc: "each member's latest reminder, by member id"
  attr :batch, :map, default: nil, doc: "the last reminders sent"
  attr :batch_sender, :string, default: nil
  attr :adding, :atom, default: nil, doc: "Activity.adding/3: :open, :published, or nil"
  attr :selected, :any, required: true, doc: "the checked members' ids"
  attr :choice, :string, default: nil, doc: "the change picked, an action's value"
  attr :step, :atom, default: nil, doc: "the open step's action, or nil for the tab"
  attr :user, :any, required: true
  attr :service, :string, required: true
  attr :filter, ActivityMembersFilterViewModel, required: true, doc: "the filter bar's choices"
  attr :groups, :list, required: true, doc: "the team's groups as `{title, id}`"
  attr :group_ids, :any, required: true, doc: "the group's member ids, or nil for no filter"

  @doc """
  The tab, drawn by Web.ActivityLive's page. The counts are the panel's line, on every
  tab. Before the start: one table by reply, then name, with how each replied and when,
  New for the last 24 hours. From the start: a table for each attendance, with each
  attended member's times.
  """
  def members_tab(assigns) do
    ctx = %{activity: assigns.activity, team: assigns.team, now: assigns.now}

    actions =
      offered(%{
        team_admin?: assigns.team_admin?,
        activity: assigns.activity,
        current_team: assigns.team,
        now: assigns.now
      })

    checked = checked(assigns)
    action = Enum.find(actions, &(&1.value() == assigns.choice))
    shown = shown(assigns)

    assigns =
      assign(assigns,
        shown: shown,
        filter_form: to_form(%{"group" => assigns.filter.group}, as: "form"),
        filter_count: filter_count(shown, assigns),
        timezone: assigns.team.timezone,
        ctx: ctx,
        actions: actions,
        changeable?: assigns.started? and actions != [],
        checked: checked,
        action: action,
        count: if(action, do: action.count(checked), else: 0)
      )

    assigns =
      assign(assigns,
        confirm: if(assigns.count > 0, do: action.confirm(ctx, checked), else: %{}),
        locked?:
          assigns.team_admin? and assigns.started? and Activity.locked?(assigns.activity) and
            !assigns.activity.deleted_at
      )

    ~H"""
    <section id="activity-members">
      <.live_component
        :if={@step}
        module={@step}
        id="members-step"
        team={@team}
        activity={@activity}
        user={@user}
        checked={@checked}
        back={members_path(@team, @activity, @filter)}
      />
      <div :if={!@step}>
        <p :if={@batch} id="members-batch" class="hint">
          {batch_text(@batch, @batch_sender, @timezone)}
        </p>
        <%!-- From the copy, which can be 10 minutes old; the send refuses it too. --%>
        <p :if={@adding == :published and !@started?} id="members-published" class="hint mb-4">
          Published, so nobody can be added. {D4H.unpublish_text(@team)}
        </p>
        <p :if={@locked?} id="members-locked" class="hint mb-4">
          Published, so attendance cannot be changed. {D4H.unpublish_text(@team)}
        </p>
        <p :if={@members == [] and @adding != :published} id="members-empty" class="hint">
          {if @started?, do: "Nobody attended.", else: "Nobody has signed up yet."}
        </p>
        <p :if={@adding == :open} class="action">
          <.a
            id="members-add"
            navigate={~p"/teams/#{@team}/activities/#{@activity.id}/members/add"}
          >Add members</.a>
        </p>
        <p :if={@adding == :open and !@started? and @members != []} class="action">
          <.a
            id="members-remove"
            navigate={~p"/teams/#{@team}/activities/#{@activity.id}/members/remove"}
          >Remove members</.a>
        </p>
        <.filter_bar
          :if={@members != [] and @groups != []}
          for={@filter_form}
          id="members-filter"
          count={@filter_count}
          clear={members_path(@team, @activity, %ActivityMembersFilterViewModel{})}
          path_fn={
            &members_path(
              @team,
              @activity,
              ActivityMembersFilterViewModel.validate(Map.new(&1), @groups)
            )
          }
        >
          <:filter
            field={@filter_form[:group]}
            label="Group"
            type="combobox"
            options={@groups}
            default=""
          />
        </.filter_bar>
        <.empty_state
          :if={@members != [] and @shown == []}
          id="members-none-shown"
          title="No members match"
        >
          Change the group.
        </.empty_state>
        <.reply_table
          :if={!@started? and @shown != []}
          activity={@activity}
          team={@team}
          members={@shown}
          standings={@standings}
          now={@now}
          reminded={@reminded}
        />
        <.form
          :if={@changeable? and @shown != []}
          for={%{}}
          id="members-change-form"
          phx-change="tick"
          phx-submit="apply"
        >
          <.attendance_tables
            activity={@activity}
            team={@team}
            members={@shown}
            standings={@standings}
            selected={@selected}
            changeable?={true}
          />
          <div id="members-change" class="mt-8">
            <.input
              type="radios"
              id="members-change-choice"
              name="change"
              label="Change the checked members"
              value={@choice}
              options={for a <- @actions, do: {a.label(), a.value(), a.hint(@ctx)}}
            />
            <.button
              id="members-change-send"
              variant={if @action, do: @action.variant(), else: :primary}
              disabled={@count == 0}
              phx-disable-with={
                if @action && @action.variant() == :danger, do: "Removing…", else: "Saving…"
              }
              {@confirm}
            >
              {if @count > 0, do: @action.button(@count), else: "Change members"}
            </.button>
          </div>
        </.form>
        <.attendance_tables
          :if={@started? and !@changeable? and @shown != []}
          activity={@activity}
          team={@team}
          members={@shown}
          standings={@standings}
          selected={@selected}
          changeable?={false}
        />
      </div>
    </section>
    """
  end

  attr :activity, :map, required: true
  attr :team, :any, required: true
  attr :members, :list, required: true
  attr :standings, :map, required: true
  attr :now, :any, required: true
  attr :reminded, :map, required: true

  # Before the start: one table, by reply and then name (#444).
  defp reply_table(assigns) do
    assigns = assign(assigns, timezone: assigns.team.timezone)

    ~H"""
    <.table
      id="members-table"
      rows={@members}
      row_id={&"member-row-#{&1.member.id}"}
      class="table-striped w-fit"
    >
      <:col :let={row} label="Member">
        <.member_cell
          id={"member-standing-#{row.member.id}"}
          member={row.member}
          team={@team}
          standing={@standings[row.member.id]}
          path={member_path(@team, @activity, row.member)}
        />
      </:col>
      <:col :let={row} label="Reply" class="whitespace-nowrap">
        <span class={["marker", "marker-#{Reply.marker(row.status)}"]}>
          {Reply.status_text(row.status, false)}
        </span>
      </:col>
      <:col :let={row} label="Replied" class="whitespace-nowrap">
        {Format.month_day_time(row.replied_at, @timezone)}
        <span
          :if={row.status == "requested" and @reminded[row.member_id]}
          id={"member-reminded-#{row.member.id}"}
          class="hint"
        >
          {reminded_text(@reminded[row.member_id], @timezone)}
        </span>
        <.badge
          :if={ActivityMembers.new?(row, @now)}
          kind={:primary}
          title="Replied in the last 24 hours"
        >
          New
        </.badge>
      </:col>
    </.table>
    """
  end

  attr :activity, :map, required: true
  attr :team, :any, required: true
  attr :members, :list, required: true
  attr :standings, :map, required: true
  attr :selected, :any, required: true
  attr :changeable?, :boolean, required: true

  # From the start: Attended with each member's times, then Absent, then No reply, each
  # with select all for a team admin who can change them. A name labels its checkbox then;
  # otherwise it links to the member's page.
  defp attendance_tables(assigns) do
    assigns =
      assign(assigns,
        timezone: assigns.team.timezone,
        groups:
          for(
            status <- ActivityMembers.statuses(),
            rows = ActivityMembers.only(assigns.members, status),
            rows != [],
            do: {status, rows}
          )
      )

    ~H"""
    <div :for={{status, rows} <- @groups} class="mb-6">
      <.table
        id={"members-#{table_id(status)}"}
        rows={rows}
        row_id={&"member-row-#{&1.member.id}"}
        class="table-striped"
      >
        <:col :let={row} :if={@changeable?} label="" class="w-px" select_all>
          <input
            type="checkbox"
            id={"members-select-#{row.member.id}"}
            name="member_ids[]"
            value={row.member.id}
            checked={MapSet.member?(@selected, row.member.id)}
          />
        </:col>
        <:col :let={row} label={Reply.status_text(status, true)}>
          <.member_cell
            id={"member-standing-#{row.member.id}"}
            member={row.member}
            team={@team}
            standing={@standings[row.member.id]}
            path={member_path(@team, @activity, row.member)}
            label_for={if @changeable?, do: "members-select-#{row.member.id}"}
          />
        </:col>
        <:col
          :let={row}
          :if={status == "attending"}
          label="Start"
          align="right"
          class="whitespace-nowrap"
        >
          {attended_start(row, @activity, @timezone)}
        </:col>
        <:col
          :let={row}
          :if={status == "attending"}
          label="Finish"
          align="right"
          class="whitespace-nowrap"
        >
          {Format.time_short(row.finished_at, @timezone)}
        </:col>
        <:col
          :let={row}
          :if={status == "attending"}
          label="Hours"
          align="right"
          class="w-px whitespace-nowrap"
        >
          <.hours_cell minutes={row.duration_in_minutes} />
        </:col>
      </.table>
      <%!-- The Hours column's sum, exact as Service.Format.duration/1 writes the minutes. --%>
      <p
        :if={status == "attending" and attended_minutes(rows) > 0}
        id="members-hours"
        class="hint mt-2"
      >
        {Format.duration(attended_minutes(rows))} in total
      </p>
    </div>
    """
  end

  # "13 members", or with a group "3 of 13 members, in Team leaders".
  defp filter_count(shown, %{members: members, filter: filter, groups: groups}) do
    all = members |> length() |> Format.count(one: "%d member", many: "%d members")

    case Enum.find(groups, fn {_title, id} -> id == filter.group end) do
      nil -> all
      {title, _id} -> "#{shown |> length() |> Format.number()} of #{all}, in #{title}"
    end
  end

  defp table_id("attending"), do: "attended"
  defp table_id("absent"), do: "absent"
  defp table_id("requested"), do: "no-reply"

  defp member_path(team, activity, member),
    do:
      ~p"/teams/#{team}/members/#{member.id}?when=#{Calendar.strftime(activity.started_at, "%Y")}"

  defp attended_minutes(rows), do: Enum.sum_by(rows, &(&1.duration_in_minutes || 0))

  # A member's own start; its date only when it isn't the activity's day.
  defp attended_start(row, activity, timezone) do
    if ActivityMembers.same_day?(row.started_at, activity.started_at, timezone),
      do: Format.time_short(row.started_at, timezone),
      else: Format.month_day_time(row.started_at, timezone)
  end

  # "4 sent Oct 26, 18:02 by Alex Chen · 2 replied since"
  # While none has gone yet: "4 sending Oct 26, 18:02 by Alex Chen".
  defp batch_text(batch, sender, timezone) do
    all_sending? = batch.sent == 0 and batch.sending > 0

    sent =
      if(all_sending?,
        do: Format.count(batch.sending, one: "%d sending", many: "%d sending"),
        else: Format.count(batch.sent, one: "%d sent", many: "%d sent")
      ) <>
        " " <>
        Format.month_day_time(batch.sent_at, timezone) <>
        if(sender, do: " by #{sender}", else: "")

    [
      sent,
      batch.sending > 0 && !all_sending? &&
        Format.count(batch.sending, one: "%d sending", many: "%d sending"),
      batch.failed > 0 && Format.count(batch.failed, one: "%d failed", many: "%d failed"),
      Format.count(batch.replied_since, one: "%d replied since", many: "%d replied since")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp reminded_text(%Reminder{status: :failed}, _timezone), do: "Reminder failed"
  defp reminded_text(%Reminder{status: :queued}, _timezone), do: "Reminder sending"

  defp reminded_text(%Reminder{sent_at: sent_at}, timezone),
    do: "Reminded " <> Format.month_day(sent_at, timezone)
end
