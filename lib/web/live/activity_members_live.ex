defmodule Web.ActivityMembersLive do
  @moduledoc """
  An activity's Members tab: who it invites and how they replied, and from the start its
  attendance (#766). Web.ActivityLive draws the page around it, as it does History; this
  module owns the tab: the members checked, the change picked, and which step is open.

  Before the start it's a table per reply, Signed up, Can't make it, then No reply (#895);
  from it, a table for each attendance, Attended, Absent, then No reply (#766). No reply
  comes last, next to the list, as Travel puts Not set. Everyone sees them. Team admins
  check members in them and act on them under the tables: one list and one button, as on
  Travel. Before the start the list emails or removes them, Send a reminder, Send an
  update, and Remove from the activity, each a step; from the start until the activity
  is published it changes their attendance. Add members has its own page.

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

  - The button patches to the step's route, and the step takes the page under its own
    title. Back patches to the tab, and the ticks are still there.
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
  alias App.Model.Standing
  alias App.Operation.ChangeAttendance
  alias App.ViewData.ActivityMembers
  alias App.ViewModel.ActivityMembersFilterViewModel
  alias Service.Format
  alias Web.ActivityLive
  alias Web.ActivityMembersLive.Absent
  alias Web.ActivityMembersLive.Attended
  alias Web.ActivityMembersLive.Remind
  alias Web.ActivityMembersLive.Remove
  alias Web.ActivityMembersLive.RemoveBeforeStart
  alias Web.ActivityMembersLive.Update
  alias Web.Components.Reply

  @actions [Remind, Update, RemoveBeforeStart, Attended, Absent, Remove]

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
     socket
     |> assign(retiring: Standing.retiring_ids(socket.assigns.current_team))
     |> assign_filter(params)
     |> keep_ticks()
     |> open_step(socket.assigns.live_action)}
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

    ctx = ctx(socket.assigns)

    if action && action.count(ctx, checked) > 0 do
      assign(socket,
        step: action,
        choice: action.value(),
        page_title: "#{socket.assigns.activity.title} · #{action.label()}"
      )
    else
      socket
      |> assign(step: nil)
      |> put_flash(:error, "Select the members again.")
      |> push_patch(to: tab_path(socket.assigns))
    end
  end

  # What the actions read: the activity, its team, now, and the team's retiring members.
  defp ctx(assigns),
    do: %{
      activity: assigns.activity,
      team: assigns.current_team,
      now: assigns.now,
      retiring: assigns.retiring
    }

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
    ctx = ctx(socket.assigns)
    checked = checked(socket.assigns)
    count = action.count(ctx, checked)

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

  # A step's error it stays open for, such as a message too long.
  def handle_info({:step_flash, kind, text}, socket),
    do: {:noreply, put_flash(socket, kind, text)}

  # Swoosh's test adapter tells each process an email came from, this one included.
  def handle_info({:email, _email}, socket), do: {:noreply, socket}

  def handle_info(message, socket), do: ActivityLive.handle_info(message, socket)

  # A step takes the page, under its own title; the tab is Web.ActivityLive's page.
  def render(%{step: nil} = assigns), do: ActivityLive.render(assigns)

  def render(assigns) do
    assigns = assign(assigns, back: tab_path(assigns))

    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item label={@activity.ref_id} path={~p"/teams/#{@current_team}/activities/#{@activity.id}"} />
      <:item label="Members" path={@back} />
      <:item label={@step.label()} />
    </.breadcrumbs>
    <h1 class="title">{@step.label()}</h1>
    <p class="lead">
      {@activity.title} · {Format.datetime_medium(@activity.started_at, @current_team.timezone)}
    </p>
    <.live_component
      module={@step}
      id="members-step"
      team={@current_team}
      activity={@activity}
      user={@current_user}
      checked={checked(assigns)}
      standings={@standings}
      counts={@counts}
      service={@service}
      back={@back}
    />
    """
  end

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
  attr :retiring, :any, required: true, doc: "the team's retiring member ids"
  attr :filter, ActivityMembersFilterViewModel, required: true, doc: "the filter bar's choices"
  attr :groups, :list, required: true, doc: "the team's groups as `{title, id}`"
  attr :group_ids, :any, required: true, doc: "the group's member ids, or nil for no filter"

  @doc """
  The tab, drawn by Web.ActivityLive's page. The counts are the panel's line, on every
  tab. A table per status: before the start each reply, with when each replied, New for
  the last 24 hours, and the last reminder; from the start each attendance, with each
  attended member's times. Before the start the list starts on its first choice, so the
  button always says what it does.
  """
  def members_tab(assigns) do
    ctx = %{
      activity: assigns.activity,
      team: assigns.team,
      now: assigns.now,
      retiring: assigns.retiring
    }

    actions =
      offered(%{
        team_admin?: assigns.team_admin?,
        activity: assigns.activity,
        current_team: assigns.team,
        now: assigns.now,
        retiring: assigns.retiring
      })

    checked = checked(assigns)

    action =
      Enum.find(actions, &(&1.value() == assigns.choice)) ||
        if(!assigns.started?, do: List.first(actions))

    shown = shown(assigns)

    assigns =
      assign(assigns,
        shown: shown,
        filter_form: to_form(%{"group" => assigns.filter.group}, as: "form"),
        filter_count: filter_count(shown, assigns),
        timezone: assigns.team.timezone,
        ctx: ctx,
        actions: actions,
        changeable?: actions != [],
        checked: checked,
        action: action,
        count: if(action, do: action.count(ctx, checked), else: 0)
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
      <.form
        :if={@changeable? and @shown != []}
        for={%{}}
        id="members-change-form"
        phx-change="tick"
        phx-submit="apply"
      >
        <.member_tables
          activity={@activity}
          team={@team}
          members={@shown}
          standings={@standings}
          started?={@started?}
          now={@now}
          reminded={@reminded}
          selected={@selected}
          changeable?={true}
        />
        <div id="members-change" class="mt-8">
          <.input
            type="radios"
            id="members-change-choice"
            name="change"
            label={if @started?, do: "Change the checked members", else: "For the checked members"}
            value={@action && @action.value()}
            options={for a <- @actions, do: {a.label(), a.value(), a.hint(@ctx)}}
          />
          <.button
            id="members-change-send"
            variant={if @action, do: @action.variant(), else: :primary}
            disabled={@count == 0}
            phx-disable-with={send_waiting(@action)}
            {@confirm}
          >
            {if @count > 0, do: @action.button_text(@count), else: idle_text(@action, @started?)}
          </.button>
        </div>
      </.form>
      <.member_tables
        :if={!@changeable? and @shown != []}
        activity={@activity}
        team={@team}
        members={@shown}
        standings={@standings}
        started?={@started?}
        now={@now}
        reminded={@reminded}
        selected={@selected}
        changeable?={false}
      />
    </section>
    """
  end

  # The button while it waits: a step opens at once, and a change in place writes.
  defp send_waiting(nil), do: "Saving…"

  defp send_waiting(action) do
    case {action.run(), action.variant()} do
      {{:step, _live_action}, _variant} -> "Opening…"
      {_run, :danger} -> "Removing…"
      _in_place -> "Saving…"
    end
  end

  # With nobody it reaches: before the start the choice's own, "Remind 0 members".
  defp idle_text(action, false = _started?) when action != nil, do: action.button_text(0)
  defp idle_text(_action, _started?), do: "Change members"

  attr :activity, :map, required: true
  attr :team, :any, required: true
  attr :members, :list, required: true
  attr :standings, :map, required: true
  attr :started?, :boolean, required: true
  attr :now, :any, required: true
  attr :reminded, :map, required: true
  attr :selected, :any, required: true
  attr :changeable?, :boolean, required: true

  # A table per status, each with select all for a team admin who can act on them. Before
  # the start: Signed up and Can't make it with Replied (#444), then No reply, with the
  # last reminder once anyone in it has one. From the
  # start: Attended with each member's times, then Absent, then No reply. A name labels
  # its checkbox then; otherwise it links to the member's page.
  defp member_tables(assigns) do
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
        id={"members-#{table_id(status, @started?)}"}
        rows={rows}
        row_id={&"member-row-#{&1.member.id}"}
        class={if @started?, do: "table-striped", else: "table-striped w-fit"}
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
        <:col :let={row} label={Reply.status_text(status, @started?)}>
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
          :if={!@started? and status != "requested"}
          label="Replied"
          class="whitespace-nowrap"
        >
          {Format.month_day_time(row.replied_at, @timezone)}
          <.badge
            :if={ActivityMembers.new?(row, @now)}
            kind={:primary}
            title="Replied in the last 24 hours"
          >
            New
          </.badge>
        </:col>
        <:col
          :let={row}
          :if={!@started? and status == "requested" and reminded?(rows, @reminded)}
          label="Reminder"
          class="whitespace-nowrap"
        >
          <span
            :if={@reminded[row.member_id]}
            id={"member-reminded-#{row.member.id}"}
            class="hint"
          >
            {reminded_text(@reminded[row.member_id], @timezone)}
          </span>
        </:col>
        <:col
          :let={row}
          :if={@started? and status == "attending"}
          label="Start"
          align="right"
          class="whitespace-nowrap"
        >
          {attended_start(row, @activity, @timezone)}
        </:col>
        <:col
          :let={row}
          :if={@started? and status == "attending"}
          label="Finish"
          align="right"
          class="whitespace-nowrap"
        >
          {Format.time_short(row.finished_at, @timezone)}
        </:col>
        <:col
          :let={row}
          :if={@started? and status == "attending"}
          label="Hours"
          align="right"
          class="w-px whitespace-nowrap"
        >
          <.hours_cell minutes={row.duration_in_minutes} />
        </:col>
      </.table>
      <%!-- The Hours column's sum, exact as Service.Format.duration/1 writes the minutes. --%>
      <p
        :if={@started? and status == "attending" and attended_minutes(rows) > 0}
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

  defp table_id("attending", false), do: "signed-up"
  defp table_id("absent", false), do: "cant-make-it"
  defp table_id("attending", true), do: "attended"
  defp table_id("absent", true), do: "absent"
  defp table_id("requested", _started?), do: "no-reply"

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

  defp reminded?(rows, reminded), do: Enum.any?(rows, &reminded[&1.member_id])

  defp reminded_text(%Reminder{status: :failed}, _timezone), do: "Reminder failed"
  defp reminded_text(%Reminder{status: :queued}, _timezone), do: "Reminder sending"

  defp reminded_text(%Reminder{sent_at: sent_at}, timezone),
    do: "Reminded " <> Format.month_day(sent_at, timezone)
end
