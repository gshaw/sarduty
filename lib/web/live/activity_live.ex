defmodule Web.ActivityLive do
  use Web, {:live_view_app_layout, access: :team}

  import Web.Components.ActivityMap
  import Web.Components.CopyButton
  import Web.Components.ActivityPanel
  import Web.Components.OpenInMaps
  import Web.Components.StatSwitch

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Coordinate
  alias App.Model.EquipmentUsage
  alias App.Model.Member
  alias App.Model.Reminder
  alias App.Operation.SendReminders
  alias App.Repo
  alias App.ViewData.ActivityMembers
  alias App.ViewData.ActivityReminders
  alias Service.Format
  alias Web.Components.ActivityMap
  alias Web.Components.Reply
  alias Web.Components.ReplyControl

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  # Members open it too (#406): the same activity, facts, and people a team admin sees.
  # Under the title, everyone gets the counts, and a member it invites gets their reply
  # until the start (#444). Under the map, Members lists who is invited and how they
  # replied, filtered by `?view=`. Team admins also get Take attendance, its history,
  # actions, and the links to member and equipment pages. A member never gets an
  # activity D4H has deleted; a team admin sees it under a banner.
  def handle_params(params, _uri, socket) do
    %{current_team: team, team_admin?: team_admin?} = socket.assigns
    activity = fetch_activity(team, params["id"])

    if activity.deleted_at && !team_admin?, do: raise(Web.Status.NotFound)

    now = DateTime.utc_now()

    socket =
      socket
      |> assign(
        page_title: activity.title,
        activity: activity,
        now: now,
        coming?: DateTime.after?(activity.started_at, now),
        hours_tags: Activity.hours_tags(team),
        usages: EquipmentUsage.for_activity(activity),
        map: build_map(activity),
        replier: Reply.replier(socket.assigns, now),
        members_view: view_status(params["view"])
      )
      |> assign_people()

    {:noreply, socket}
  end

  # Who is invited and how they replied, again after a reply.
  defp assign_people(socket) do
    %{activity: activity, replier: replier} = socket.assigns
    members = ActivityMembers.load(activity)
    attendances = ActivityMembers.only(members, "attending")

    socket
    |> assign(
      members: members,
      attendances: attendances,
      attendance_count: length(attendances),
      counts: ActivityMembers.counts(members),
      invitation: replier && Attendance.invitation(activity, replier)
    )
    |> assign_reminders(members)
  end

  # Reminders a team admin sends (#444): each member's latest, the last batch, and the
  # round they can send now, before the start.
  defp assign_reminders(socket, members) do
    %{activity: activity, current_team: team, coming?: coming?, now: now} = socket.assigns
    reminders = Reminder.for_activity(activity)
    batch = ActivityReminders.last_batch(reminders, members)

    assign(socket,
      reminded: ActivityReminders.latest(reminders),
      batch: batch,
      batch_sender: batch && sender_name(team, batch.sent_by_user, now),
      next_round:
        socket.assigns.team_admin? && coming? && !activity.deleted_at &&
          ActivityReminders.next_round(members, reminders, now)
    )
  end

  defp sender_name(_team, nil, _now), do: nil

  defp sender_name(team, user, now) do
    case Member.find_by_email(team, user.email, now) do
      %Member{name: name} -> name
      nil -> user.email
    end
  end

  def handle_event("remind", %{"round" => round}, socket) when round in ["1", "2"] do
    %{current_team: team, activity: activity, current_user: user} = socket.assigns
    now = DateTime.utc_now()

    case SendReminders.call(team, activity, user, String.to_integer(round), now) do
      {:ok, _reminders} -> {:noreply, socket |> assign(now: now) |> assign_people()}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  # The view's word in the URL, the same before and after the start, as a D4H status.
  @views %{
    "signed-up" => "attending",
    "attended" => "attending",
    "cant-make-it" => "absent",
    "absent" => "absent",
    "no-reply" => "requested"
  }

  defp view_status(param), do: Map.get(@views, param)

  defp view_param("attending", false = _started?), do: "signed-up"
  defp view_param("attending", true), do: "attended"
  defp view_param("absent", false), do: "cant-make-it"
  defp view_param("absent", true), do: "absent"
  defp view_param("requested", _started?), do: "no-reply"

  def handle_info({:replied, _attendance}, socket), do: {:noreply, assign_people(socket)}

  def handle_info({:reply_failed, text}, socket), do: {:noreply, put_flash(socket, :error, text)}

  # Swoosh's test adapter tells each process a reminder came from, this one included.
  def handle_info({:email, _email}, socket), do: {:noreply, socket}

  @kinds %{"incident" => :incident, "exercise" => :exercise, "event" => :event}

  # One dot on the same light and dark map as the dashboard. Zoom 10 shows the town around it.
  defp build_map(activity) do
    case Coordinate.build(activity.coordinate) do
      {lat, lng} when {lat, lng} != {0.0, 0.0} ->
        point = %{
          lat: lat,
          lng: lng,
          kind: Map.get(@kinds, activity.activity_kind, :event),
          recent: true,
          tip: activity.title
        }

        ActivityMap.build([point], {640, 480}, max_zoom: 10.0)

      _none ->
        nil
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item label={"#{@activity.ref_id}"} />
    </.breadcrumbs>

    <h1 class="title">{@activity.title}</h1>
    <.banner
      :if={@activity.deleted_at}
      id="deleted-in-d4h"
      kind={:danger}
      title="Deleted"
    >
      <p>
        SAR Duty saw it was gone on {Service.Format.date_long(
          @activity.deleted_at,
          @activity.team.timezone
        )}.
      </p>
    </.banner>
    <.activity_panel
      id="activity-panel"
      activity={@activity}
      team={@activity.team}
      now={@now}
      counts={@counts}
      take_attendance?={Activity.take_attendance?(@activity, @team_admin?, @now)}
    >
      <:reply :if={Reply.open?(@invitation, @activity, @now)}>
        <.live_component
          module={ReplyControl}
          id="activity-reply"
          team={@current_team}
          activity={@activity}
          member={@replier}
          invitation={@invitation}
          user={@current_user}
          viewing_as={@viewing_as}
        />
      </:reply>
    </.activity_panel>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content
          activity={@activity}
          maps_app={@current_user.maps_app}
          hours_tags={@hours_tags}
          attendances={@attendances}
          attendance_count={@attendance_count}
          team_admin?={@team_admin?}
        />
      </aside>
      <main class="content-2/3">
        <.main_content activity={@activity} hours_tags={@hours_tags} map={@map} />
        <.members_section
          activity={@activity}
          members={@members}
          counts={@counts}
          view={@members_view}
          started?={!@coming?}
          now={@now}
          team_admin?={@team_admin?}
          reminded={@reminded}
          batch={@batch}
          batch_sender={@batch_sender}
          next_round={@next_round}
        />
        <.equipment_section activity={@activity} usages={@usages} team_admin?={@team_admin?} />
      </main>
    </div>
    """
  end

  attr :activity, :map, required: true
  attr :maps_app, :string, required: true

  # The address and the latitude and longitude, each with a copy button. The map link goes
  # on the latitude and longitude, which pin the exact spot.
  defp place(assigns) do
    ~H"""
    <div :if={@activity.address}>
      <dt>Address</dt>
      <dd>
        {@activity.address}<.copy_button
          id="activity-copy-address"
          value={@activity.address}
          label="Copy address"
        />
        <.open_in_maps
          :if={!Activity.pin(@activity)}
          id="activity-maps"
          app={@maps_app}
          address={@activity.address}
        />
      </dd>
    </div>
    <div :if={Activity.pin(@activity)}>
      <dt>Latitude and longitude</dt>
      <dd>
        {@activity.coordinate}<.copy_button
          id="activity-copy-coordinate"
          value={@activity.coordinate}
          label="Copy latitude and longitude"
        />
        <.open_in_maps
          id="activity-maps"
          app={@maps_app}
          coordinate={Activity.pin(@activity)}
          label={@activity.title}
        />
      </dd>
    </div>
    """
  end

  attr :activity, :map, required: true
  attr :maps_app, :string, required: true
  attr :hours_tags, :map, required: true
  attr :attendances, :list, required: true
  attr :attendance_count, :integer, required: true
  attr :team_admin?, :boolean, default: false

  def sidebar_content(assigns) do
    ~H"""
    <dl>
      <dt>Kind</dt>
      <dd><.activity_badges activity={@activity} /></dd>

      <div :if={@attendance_count > 0}>
        <dt>Attendance</dt>
        <dd>
          {Service.Format.count(@attendance_count, one: "%d member", many: "%d members")} · {format_total_effort(
            @attendances
          )} in total
        </dd>
      </div>

      <dt>Start</dt>
      <dd>
        {Service.Format.datetime_medium(@activity.started_at, @activity.team.timezone)}
      </dd>
      <dt>Finish</dt>
      <dd>
        {Service.Format.datetime_medium(@activity.finished_at, @activity.team.timezone)}
      </dd>
      <dt>Duration</dt>
      <dd>{format_activity_duration(@activity)}</dd>

      <div :if={hours_type = activity_hours_type(@activity, @hours_tags)}>
        <dt>SARVAC hours</dt>
        <dd>{hours_type}</dd>
      </div>

      <.place activity={@activity} maps_app={@maps_app} />

      <dt>Links</dt>
      <dd>
        <ul id="activity-links" class="action-list">
          <li :if={!@activity.deleted_at}>
            <.a
              id="activity-calendar"
              href={~p"/teams/#{@activity.team}/activities/#{@activity.id}/calendar"}
            >Add to calendar</.a>
          </li>
          <li :if={!D4H.records?(@activity.team)}>
            <.a external={true} href={D4H.activity_url(@activity.team, @activity)}>Open {D4H.service_name(
              @activity.team
            )} activity</.a>
          </li>
        </ul>
      </dd>
      <%!-- Team admins only: the history can hold contact details and addresses. --%>
      <div :if={@team_admin?}>
        <dt>History</dt>
        <dd>
          <ul class="action-list">
            <li>
              <.a
                id="activity-history-link"
                navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/history"}
              >Changes to this activity</.a>
            </li>
          </ul>
        </dd>
      </div>

      <%!-- Each action reads or writes the activity in D4H, which no longer has it. --%>
      <dt :if={@team_admin? and !@activity.deleted_at}>Actions</dt>
      <dd :if={@team_admin? and !@activity.deleted_at}>
        <ul id="activity-actions" class="action-list">
          <li>
            <.a
              id="activity-send-attendance"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/attendance"}
            >Send attendance</.a>
          </li>
          <li :if={D4H.records?(@activity.team)}>
            <.a
              id="activity-edit"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/edit"}
            >Change or delete</.a>
          </li>
          <%!-- D4H refuses tags on a published activity (#358). --%>
          <li :if={!D4H.records?(@activity.team) and D4H.tags_locked?(@activity.team, @activity)}>
            <div id="activity-tags-in-d4h" class="hint">
              Published, so change its tags in {D4H.service_name(@activity.team)}.
            </div>
          </li>
          <li :if={!D4H.tags_locked?(@activity.team, @activity)}>
            <.a
              id="activity-change-tags"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/tags"}
            >Change tags</.a>
          </li>
          <li>
            <.a
              id="activity-apply-template"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/templates"}
            >Apply a template</.a>
          </li>
          <li>
            <.a navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/mileage"}>Mileage report</.a>
          </li>
        </ul>
      </dd>
    </dl>
    """
  end

  attr :activity, :map, required: true
  attr :hours_tags, :map, required: true
  attr :map, :map, default: nil

  def main_content(assigns) do
    ~H"""
    <div>
      <div class="mb-4"><.activity_tags activity={@activity} hours_tags={@hours_tags} /></div>

      <div :if={@map} class="measure mb-4">
        <.activity_map id="activity-map" map={@map} label="Map of activity" />
      </div>

      <div class="mb-4">
        <.markdown content={@activity.description} />
      </div>
    </div>
    """
  end

  attr :activity, :map, required: true
  attr :members, :list, required: true
  attr :counts, :map, required: true
  attr :view, :string, default: nil, doc: "the D4H status showing, nil for All"
  attr :started?, :boolean, required: true
  attr :now, :any, required: true
  attr :team_admin?, :boolean, default: false
  attr :reminded, :map, default: %{}, doc: "each member's latest reminder, by member id"
  attr :batch, :map, default: nil, doc: "the last reminders sent"
  attr :batch_sender, :string, default: nil
  attr :next_round, :any, default: nil, doc: "{round, plan} a team admin can send now"

  # Who the activity invites, as counts that filter one table (#444). Before the start:
  # how each replied and when, New for the last 24 hours. From the start: D4H's
  # attendance, with each member's times. A column every row would repeat goes.
  def members_section(assigns) do
    rows = ActivityMembers.only(assigns.members, assigns.view)

    assigns =
      assign(assigns,
        rows: rows,
        timezone: assigns.activity.team.timezone,
        reminded_shown?:
          Enum.any?(rows, &(&1.status == "requested" and assigns.reminded[&1.member_id]))
      )

    ~H"""
    <section id="activity-members" class="mt-8">
      <.heading_row id="members-heading">
        <h2 class="heading">Members</h2>
        <:note :if={@batch}>
          <span id="members-batch">{batch_text(@batch, @batch_sender, @timezone)}</span>
        </:note>
        <:action :if={@next_round}>
          <.reminders_button activity={@activity} next_round={@next_round} />
        </:action>
      </.heading_row>
      <p :if={@members == []} id="members-empty" class="hint">
        {if @started?, do: "Nobody attended.", else: "Nobody has signed up yet."}
      </p>
      <.stat_switch
        :if={@members != []}
        id="members-switch"
        label={if @started?, do: "Attendance", else: "Replies"}
      >
        <:view
          id="members-view-all"
          patch={members_path(@activity, nil)}
          current={@view == nil}
          count={length(@members)}
        >
          All
        </:view>
        <:view
          :for={status <- ActivityMembers.statuses()}
          id={"members-view-#{view_param(status, @started?)}"}
          patch={members_path(@activity, view_param(status, @started?))}
          current={@view == status}
          count={@counts[String.to_existing_atom(status)]}
          marker={Reply.marker(status)}
        >
          {Reply.status_text(status, @started?)}
        </:view>
      </.stat_switch>
      <.table
        :if={@rows != []}
        id="members-table"
        rows={@rows}
        row_id={&"member-row-#{&1.member.id}"}
        class="table-striped w-fit"
      >
        <:col :let={row} label="Name" class="whitespace-nowrap">
          <.a navigate={
            ~p"/teams/#{@activity.team}/members/#{row.member.id}?when=#{Calendar.strftime(@activity.started_at, "%Y")}"
          }>{row.member.name}</.a>
        </:col>
        <:col
          :let={row}
          :if={@view == nil}
          label={if @started?, do: "Attendance", else: "Reply"}
          class="whitespace-nowrap"
        >
          <span class={["marker", "marker-#{Reply.marker(row.status)}"]}>
            {Reply.status_text(row.status, @started?)}
          </span>
        </:col>
        <:col
          :let={row}
          :if={!@started? and (@view != "requested" or @reminded_shown?)}
          label="Replied"
          class="whitespace-nowrap"
        >
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
        <:col
          :let={row}
          :if={@started? and @view in [nil, "attending"]}
          label="Start"
          align="right"
          class="whitespace-nowrap"
        >
          {attended_time(row, :start, @activity, @timezone)}
        </:col>
        <:col
          :let={row}
          :if={@started? and @view in [nil, "attending"]}
          label="Finish"
          align="right"
          class="whitespace-nowrap"
        >
          {attended_time(row, :finish, @activity, @timezone)}
        </:col>
        <:col
          :let={row}
          :if={@started? and @view in [nil, "attending"]}
          label="Duration"
          align="right"
          class="whitespace-nowrap"
        >
          {if row.status == "attending", do: Format.duration(row.duration_in_minutes)}
        </:col>
      </.table>
    </section>
    """
  end

  attr :activity, :map, required: true
  attr :next_round, :any, required: true

  # Send N reminders, or Ask again (N) for round 2, after the browser's own confirm: an
  # email can't be taken back. It names who it skips and why.
  defp reminders_button(%{next_round: {round, plan}} = assigns) do
    assigns = assign(assigns, round: round, plan: plan, count: length(plan.send))

    ~H"""
    <.button
      id="members-remind"
      phx-click="remind"
      phx-value-round={@round}
      phx-disable-with="Sending…"
      data-confirm={reminders_confirm(@round, @plan)}
    >
      {if @round == 1,
        do: Format.count(@count, one: "Send 1 reminder", many: "Send %d reminders"),
        else: "Ask again (#{Format.number(@count)})"}
    </.button>
    """
  end

  defp reminders_confirm(round, plan) do
    [confirm_ask(round, length(plan.send)), confirm_skipped(plan.skipped)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp confirm_ask(1, count) do
    Format.count(count,
      one: "Email 1 member who has not replied?",
      many: "Email %d members who have not replied?"
    ) <>
      " Each gets one email from you with I'll be there and Can't make it." <>
      " Replies to the email come to you."
  end

  defp confirm_ask(2, count) do
    Format.count(count, one: "Ask 1 member again?", many: "Ask %d members again?") <>
      " They have not replied since their first reminder." <>
      " Each gets one more email from you, the last for this activity."
  end

  defp confirm_skipped([]), do: nil

  defp confirm_skipped(skipped) do
    names = skipped |> Enum.map(&skipped_text/1) |> Format.or_list()
    "Not sent to #{names}."
  end

  defp skipped_text({member, :no_email}), do: "#{member.name} (no email)"
  defp skipped_text({member, :reminders_off}), do: "#{member.name} (reminders off)"

  # "4 sent Oct 26, 18:02 by Alex Chen · 2 replied since"
  defp batch_text(batch, sender, timezone) do
    sent =
      Format.count(batch.sent, one: "%d sent", many: "%d sent") <>
        " " <>
        Format.month_day_time(batch.sent_at, timezone) <>
        if(sender, do: " by #{sender}", else: "")

    [
      sent,
      batch.failed > 0 && Format.count(batch.failed, one: "%d failed", many: "%d failed"),
      Format.count(batch.replied_since, one: "%d replied since", many: "%d replied since")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp reminded_text(%Reminder{status: :failed}, _timezone), do: "Reminder failed"

  defp reminded_text(%Reminder{sent_at: sent_at}, timezone),
    do: "Reminded " <> Format.month_day(sent_at, timezone)

  defp members_path(activity, nil), do: ~p"/teams/#{activity.team}/activities/#{activity.id}"

  defp members_path(activity, view),
    do: ~p"/teams/#{activity.team}/activities/#{activity.id}?#{[view: view]}"

  # A member's own times once it starts; the start's date only when it isn't the
  # activity's day. Blank for anyone who didn't attend.
  defp attended_time(%{status: "attending"} = row, :start, activity, timezone) do
    if ActivityMembers.same_day?(row.started_at, activity.started_at, timezone),
      do: Format.time_short(row.started_at, timezone),
      else: Format.month_day_time(row.started_at, timezone)
  end

  defp attended_time(%{status: "attending"} = row, :finish, _activity, timezone),
    do: Format.time_short(row.finished_at, timezone)

  defp attended_time(_row, _time, _activity, _timezone), do: nil

  attr :activity, :map, required: true
  attr :usages, :list, required: true
  attr :team_admin?, :boolean, default: false

  def equipment_section(assigns) do
    ~H"""
    <section id="activity-equipment" class="mt-8">
      <.heading_row>
        <h2 class="heading">Equipment · {length(@usages)}</h2>
        <:action>
          <.button
            :if={@team_admin? and !@activity.deleted_at}
            id="activity-equipment-add"
            size={:sm}
            navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/equipment"}
          >
            Add equipment
          </.button>
        </:action>
      </.heading_row>
      <.table
        :if={@usages != []}
        id="activity-equipment-table"
        rows={@usages}
        row_id={&"usage-#{&1.id}"}
        class="table-striped w-fit"
      >
        <:col :let={usage} label="Item">
          <.a
            :if={@team_admin?}
            navigate={~p"/teams/#{@activity.team}/equipment/#{usage.equipment_item.id}"}
          >{usage.equipment_item.title}</.a>
          <span :if={!@team_admin?}>{usage.equipment_item.title}</span>
        </:col>
        <:col :let={usage} label="Type">{usage.equipment_item.kind}</:col>
        <:col :let={usage} label="Used" align="right" class="whitespace-nowrap">
          {Web.ActivityEquipmentLive.amount(usage)}
        </:col>
      </.table>
      <p :if={@usages == []} class="hint">No equipment on this activity.</p>
    </section>
    """
  end

  @doc "Sends a page that calls D4H back to a deleted activity's page."
  def leave_deleted(socket, activity) do
    socket
    |> put_flash(
      :error,
      "This activity is deleted. Nothing can be sent to it."
    )
    |> push_navigate(to: ~p"/teams/#{socket.assigns.current_team}/activities/#{activity.id}")
  end

  def fetch_activity(team, activity_id) do
    team
    |> Activity.find!(activity_id)
    |> Repo.preload(:team)
  end

  defp format_activity_duration(activity) do
    activity.started_at
    |> Service.Convert.duration_to_minutes(activity.finished_at)
    |> Service.Format.duration()
  end

  defp format_total_effort(attendances) do
    total_minutes =
      attendances
      |> Enum.map(& &1.duration_in_minutes)
      |> Enum.sum()

    rounded_minutes =
      if total_minutes > 300, do: round(total_minutes / 60) * 60, else: total_minutes

    Service.Format.duration(rounded_minutes)
  end
end
