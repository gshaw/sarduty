defmodule Web.ActivityLive do
  use Web, {:live_view_app_layout, access: :team}

  import Web.Components.ActivityMap
  import Web.Components.ChangeHistory
  import Web.Components.CopyButton
  import Web.Components.CustomFields
  import Web.Components.ActivityPanel
  import Web.Components.OpenInMaps

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.AttendanceScan
  alias App.Model.ChoreEvent
  alias App.Model.Coordinate
  alias App.Model.CustomField
  alias App.Model.EquipmentUsage
  alias App.Model.Member
  alias App.Model.Reminder
  alias App.Model.Standing
  alias App.Model.Trip
  alias App.Operation.DeleteActivity
  alias App.Operation.SendReminders
  alias App.Repo
  alias App.ViewData.ActivityMembers
  alias App.ViewData.ActivityReminders
  alias App.ViewData.ActivityTravel
  alias App.ViewData.ChangeHistory
  alias Web.Components.ActivityMap
  alias Web.Components.Reply
  alias Web.Components.ReplyControl
  alias Web.Components.TravelCheck
  alias Web.Components.TravelTab

  # A reminder's job tells the page when it's sent or failed.
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(App.PubSub, SendReminders.topic(socket.assigns.current_team))

    {:ok, socket}
  end

  # Members open it too (#406): the same activity, facts, and people a team admin sees.
  # Under the title, everyone gets the counts, and a member it invites gets their reply
  # until the start (#444). Then tabs, above both columns: Overview has the tags, map,
  # and description; Members, Web.ActivityMembersLive's, lists who is invited and how
  # they replied, and their attendance from the start (#766); Travel
  # (#230), for team admins from the start, next to Members since it's the next job;
  # Equipment what was used; Fields its D4H custom fields, when it has any or a team
  # admin can fill one in, with Change fields (#705); and History, for team admins. The
  # facts and Actions sit beside every tab, but a phone shows them on Overview only, so
  # the other tabs start with their own content. Team admins also get Take attendance,
  # Actions, and the links to member and equipment pages. A member never gets an
  # activity D4H has deleted; a team admin sees it under a banner.
  def handle_params(params, _uri, socket) do
    %{current_team: team, team_admin?: team_admin?} = socket.assigns
    activity = fetch_activity(team, params["id"])

    if activity.deleted_at && !team_admin?, do: raise(Web.Status.NotFound)
    travel? = Activity.travel?(team, activity)
    # Travel is a feature, on incidents only.
    if socket.assigns.live_action == :travel && !travel?, do: raise(Web.Status.NotFound)
    # The History tab is Web.ActivityHistoryLive's route, for team admins only.
    tab = tab(socket.assigns.live_action)

    now = DateTime.utc_now()

    socket =
      socket
      |> assign(
        page_title: page_title(activity, tab),
        activity: activity,
        travel?: travel?,
        tab: tab,
        entries: if(tab == :history, do: ChangeHistory.for_activity(team, activity), else: []),
        now: now,
        coming?: not Activity.started?(activity, now),
        hours_tags: Activity.hours_tags(team),
        usages: EquipmentUsage.for_activity(activity),
        map: build_map(activity),
        replier: Reply.replier(socket.assigns, now)
      )
      |> assign_fields()
      |> assign_people()

    {:noreply, socket}
  end

  @tabs [:overview, :members, :travel, :equipment, :fields, :history]

  # Any other live action is a step of the Members tab (Web.ActivityMembersLive).
  defp tab(action) when action in @tabs, do: action
  defp tab(_step), do: :members

  defp page_title(activity, :overview), do: activity.title
  defp page_title(activity, :members), do: "#{activity.title} · Members"
  defp page_title(activity, :travel), do: "#{activity.title} · Travel"
  defp page_title(activity, :equipment), do: "#{activity.title} · Equipment"
  defp page_title(activity, :fields), do: "#{activity.title} · Fields"
  defp page_title(activity, :history), do: "#{activity.title} · History"

  @doc """
  Who is invited and how they replied, with the counts, reminders, and Travel's badge:
  again after a reply, or a change on the Members tab.
  """
  def assign_people(socket) do
    %{activity: activity, replier: replier, current_team: team, now: now} = socket.assigns
    members = ActivityMembers.load(activity)
    team_admin? = socket.assigns.team_admin?
    attendances = ActivityMembers.only(members, "attending")

    socket
    |> assign(
      members: members,
      standings:
        Standing.visible_by_member(team, Enum.map(members, & &1.member), now, team_admin?),
      counts: ActivityMembers.counts(members),
      invitation: replier && Attendance.invitation(activity, replier),
      your_travel?:
        socket.assigns.travel? and
          your_travel?(activity, replier, socket.assigns.coming?, attendances)
    )
    |> assign_reminders(members)
    |> assign_actions()
    |> assign_travel()
  end

  # The Travel tab's badge counts the attended rows with no trip (#230), from the finish,
  # when members are home, until it's published and travel can't change.
  defp assign_travel(socket) do
    %{activity: activity, team_admin?: team_admin?, now: now} = socket.assigns
    count? = socket.assigns.travel? and team_admin? and Activity.finished_draft?(activity, now)

    assign(socket,
      travel_not_set: if(count?, do: ActivityTravel.counts(activity, now).not_set, else: 0)
    )
  end

  # Whether the panel shows the member's travel (#230): after the start, once a team
  # admin set some for them, or while it's open to them to set. TravelCheck shows which.
  defp your_travel?(_activity, nil, _coming?, _attendances), do: false
  defp your_travel?(_activity, _member, true, _attendances), do: false

  defp your_travel?(%Activity{deleted_at: %DateTime{}}, _member, _coming?, _attendances),
    do: false

  defp your_travel?(activity, member, _coming?, attendances) do
    attended? = Enum.any?(attendances, &(&1.member.id == member.id))
    (attended? and not Activity.locked?(activity)) or Trip.for_member(activity, member) != %{}
  end

  # Delete is an Actions link that opens the confirm dialog (docs/urls.md), for a Records
  # team's admins: D4H does not let SAR Duty delete activities. Send attendance shows once
  # someone has scanned (#766).
  defp assign_actions(socket) do
    %{activity: activity, current_team: team, team_admin?: team_admin?, now: now} =
      socket.assigns

    delete? = team_admin? and D4H.records?(team) and !activity.deleted_at

    assign(socket,
      delete_confirm: delete? && Web.DeleteConfirm.activity(team, activity, now),
      send_attendance?: team_admin? and AttendanceScan.any?(activity)
    )
  end

  def handle_event("delete", _params, %{assigns: %{delete_confirm: false}} = socket),
    do: {:noreply, socket}

  def handle_event("delete", _params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns

    case DeleteActivity.call(team, activity, user, DateTime.utc_now()) do
      {:ok, _activity} ->
        socket =
          socket
          |> put_flash(:info, "Deleted #{activity.title}.")
          |> push_navigate(to: ~p"/teams/#{team}/activities")

        {:noreply, socket}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  # Reminders a team admin sends (#444): each member's latest, the last batch, and
  # Send reminders while anyone has no reply, before the start (#608). Its page names
  # anyone it can't email, and why.
  defp assign_reminders(socket, members) do
    %{activity: activity, current_team: team, coming?: coming?, now: now} = socket.assigns
    reminders = Reminder.for_activity(activity)
    batch = ActivityReminders.last_batch(reminders, members)

    assign(socket,
      reminded: ActivityReminders.latest(reminders),
      batch: batch,
      batch_sender: batch && Member.name_for_user(team, batch.sent_by_user, now),
      send_reminders?:
        socket.assigns.team_admin? && coming? && !activity.deleted_at &&
          Enum.any?(members, &(&1.status == "requested")),
      send_update?: socket.assigns.team_admin? && coming? && !activity.deleted_at && members != []
    )
  end

  def handle_info({:replied, _attendance}, socket), do: {:noreply, assign_people(socket)}

  def handle_info(
        {:reminder_done, activity_id},
        %{assigns: %{activity: %{id: activity_id}}} = socket
      ),
      do: {:noreply, assign_people(socket)}

  def handle_info({:reminder_done, _other_activity}, socket), do: {:noreply, socket}

  def handle_info({:reply_failed, text}, socket), do: {:noreply, put_flash(socket, :error, text)}

  # The Travel tab and Your travel show the same rows, so a save in one reloads the other,
  # and the tab's badge counts again.
  def handle_info({:travel_flash, kind, text}, socket) do
    if socket.assigns.your_travel?,
      do: send_update(TravelCheck, id: "activity-your-travel")

    {:noreply, socket |> put_flash(kind, text) |> assign_travel()}
  end

  def handle_info({:travel_checked, text}, socket) do
    if socket.assigns.tab == :travel,
      do: send_update(TravelTab, id: "activity-travel-tab", reload: true)

    {:noreply, socket |> put_flash(:info, text) |> assign_travel()}
  end

  def handle_info({:travel_failed, text}, socket), do: {:noreply, put_flash(socket, :error, text)}

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

        ActivityMap.build([point], {960, 540}, max_zoom: 10.0)

      _none ->
        nil
    end
  end

  # The activity's D4H custom fields (#681). RESTRICTED ones show to team admins only,
  # and so do required ones left empty, on a draft incident, where they stop D4H
  # publishing it (Activity.flag_missing_fields?/1).
  # The Fields tab: the rows the viewer sees, how many of them D4H needs to publish, for
  # the count over the missing ones, and whether a team admin can change them (#705).
  defp assign_fields(socket) do
    %{current_team: team, team_admin?: team_admin?, activity: activity} = socket.assigns
    fields = CustomField.get_all(team.id, activity.activity_kind)

    assign(socket,
      field_rows: field_rows(team, activity, fields, team_admin?),
      required_fields: Enum.count(fields, &(&1.required and (team_admin? or not &1.restricted))),
      change_fields?: team_admin? and fields != [] and is_nil(activity.deleted_at)
    )
  end

  defp field_rows(team, activity, fields, team_admin?) do
    fields
    |> CustomField.rows(activity.custom_values, team.timezone,
      restricted: team_admin?,
      missing: team_admin? and Activity.flag_missing_fields?(activity)
    )
  end

  # The required fields left empty, for the Fields tab's count, from the finish until it's
  # published, as Travel's; or nil when there are none.
  defp missing_count(rows, activity, now) do
    case Activity.finished_draft?(activity, now) and Enum.count(rows, & &1.missing?) do
      false -> nil
      0 -> nil
      count -> count
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
      state?={!@activity.deleted_at}
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
      <%!-- After the start, the member's own part is their travel, where their reply was. --%>
      <:reply :if={@your_travel?}>
        <.live_component
          module={TravelCheck}
          id="activity-your-travel"
          team={@current_team}
          activity={@activity}
          member={@replier}
          user={@current_user}
          viewing_as={@viewing_as}
          now={@now}
        />
      </:reply>
    </.activity_panel>
    <%!-- Tabs above both columns. A phone shows the facts and Actions on Overview only:
         the facts, then the story, then Actions. --%>
    <.tabs label="Activity">
      <:tab
        navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}"}
        current={@tab == :overview}
      >
        Overview
      </:tab>
      <:tab
        navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/members"}
        current={@tab == :members}
      >
        Members
      </:tab>
      <:tab
        :if={@travel? and @team_admin? and (!@coming? or @tab == :travel) and !@activity.deleted_at}
        navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/travel"}
        current={@tab == :travel}
      >
        Travel<.badge :if={@travel_not_set > 0} kind={:warning}>{@travel_not_set}</.badge>
      </:tab>
      <:tab
        navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/equipment"}
        current={@tab == :equipment}
      >
        Equipment
      </:tab>
      <:tab
        :if={@field_rows != [] or @tab == :fields or @change_fields?}
        navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/fields"}
        current={@tab == :fields}
      >
        Fields<.badge
          :if={missing = missing_count(@field_rows, @activity, @now)}
          kind={:warning}
        >
          {missing}
        </.badge>
      </:tab>
      <:tab
        :if={@team_admin?}
        navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/history"}
        current={@tab == :history}
      >
        History
      </:tab>
    </.tabs>
    <div class={["activity-columns", @tab == :overview && "is-overview"]}>
      <aside id="activity-facts" class="activity-columns-facts">
        <.facts
          activity={@activity}
          maps_app={@current_user.maps_app}
          hours_tags={@hours_tags}
        />
      </aside>
      <main class="activity-columns-main">
        <.main_content
          :if={@tab == :overview}
          activity={@activity}
          hours_tags={@hours_tags}
          map={@map}
        />
        <.live_component
          :if={@tab == :travel and !@coming? and !@activity.deleted_at}
          module={TravelTab}
          id="activity-travel-tab"
          team={@current_team}
          activity={@activity}
          user={@current_user}
          service={@service}
        />
        <p :if={@tab == :travel and @coming?} id="travel-not-started" class="hint">
          Travel opens when the activity starts.
        </p>
        <Web.ActivityMembersLive.members_tab
          :if={@tab == :members}
          activity={@activity}
          team={@current_team}
          members={@members}
          standings={@standings}
          started?={!@coming?}
          now={@now}
          team_admin?={@team_admin?}
          reminded={@reminded}
          batch={@batch}
          batch_sender={@batch_sender}
          adding={Activity.adding(@activity, @team_admin?, @now)}
          selected={@selected}
          choice={@choice}
          step={@step}
          filter={@filter}
          groups={@groups}
          group_ids={@group_ids}
          user={@current_user}
          service={@service}
        />
        <.equipment_section
          :if={@tab == :equipment}
          activity={@activity}
          usages={@usages}
          team_admin?={@team_admin?}
        />
        <.custom_fields_table
          :if={@tab == :fields}
          id="activity-fields"
          rows={@field_rows}
          required={@required_fields}
        />
        <p :if={@tab == :fields and @change_fields?} class="action">
          <.a
            id="activity-fields-change"
            navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/fields/edit"}
          >Change fields</.a>
        </p>
        <.change_history
          :if={@tab == :history}
          id="activity-history"
          entries={@entries}
          timezone={@current_team.timezone}
        />
      </main>
      <aside id="activity-sidebar-end" class="activity-columns-end">
        <.sidebar_end
          activity={@activity}
          team_admin?={@team_admin?}
          change_fields?={@change_fields?}
          send_reminders?={@send_reminders?}
          send_update?={@send_update?}
          send_attendance?={@send_attendance?}
          delete_confirm={@delete_confirm}
        />
      </aside>
    </div>
    """
  end

  attr :activity, :map, required: true
  attr :maps_app, :string, required: true

  # Place: the address, then the latitude and longitude, each on its line with a copy
  # button, and one map link: to the latitude and longitude when there are some, since they
  # pin the exact spot, otherwise to the address.
  defp place(assigns) do
    assigns = assign(assigns, pin: Activity.pin(assigns.activity))

    ~H"""
    <div :if={@activity.address || @pin}>
      <dt>Place</dt>
      <dd>
        <span :if={@activity.address} class="block">
          <.copy_button
            text={@activity.address}
            id="activity-copy-address"
            value={@activity.address}
            label="Copy address"
          />
        </span>
        <span :if={@pin} class="block">
          <.copy_button
            text={@activity.coordinate}
            id="activity-copy-coordinate"
            value={@activity.coordinate}
            label="Copy latitude and longitude"
          />
        </span>
        <.open_in_maps
          :if={@pin}
          id="activity-maps"
          app={@maps_app}
          coordinate={@pin}
          label={@activity.title}
        />
        <.open_in_maps
          :if={!@pin}
          id="activity-maps"
          app={@maps_app}
          address={@activity.address}
        />
      </dd>
    </div>
    """
  end

  attr :activity, :map, required: true
  attr :maps_app, :string, required: true
  attr :hours_tags, :map, required: true

  def facts(assigns) do
    ~H"""
    <dl>
      <dt>Kind</dt>
      <dd><.activity_badges activity={@activity} /></dd>

      <dt>Start</dt>
      <dd>
        {Service.Format.datetime_medium(@activity.started_at, @activity.team.timezone)}
        <p :if={!@activity.deleted_at} class="action mb-0">
          <.a
            id="activity-calendar"
            icon="calendar-plus"
            href={~p"/teams/#{@activity.team}/activities/#{@activity.id}/calendar"}
          >Add to calendar</.a>
        </p>
      </dd>
      <dt>Finish</dt>
      <dd>
        {Service.Format.datetime_medium(@activity.finished_at, @activity.team.timezone)}
      </dd>
      <dt>Duration</dt>
      <dd>{format_activity_duration(@activity)}</dd>

      <div :if={@activity.enough_at}>
        <dt>Enough at</dt>
        <dd id="activity-enough-at">{@activity.enough_at}</dd>
      </div>
      <div :if={@activity.full_at}>
        <dt>Full at</dt>
        <dd id="activity-full-at">{@activity.full_at}</dd>
      </div>

      <div :if={hours_type = activity_hours_type(@activity, @hours_tags)}>
        <dt>Tax credit hours</dt>
        <dd>{hours_type}</dd>
      </div>

      <.place activity={@activity} maps_app={@maps_app} />
    </dl>
    """
  end

  attr :activity, :map, required: true
  attr :team_admin?, :boolean, default: false
  attr :change_fields?, :boolean, default: false, doc: "whether its kind has custom fields"
  attr :send_reminders?, :boolean, default: false, doc: "whether anyone has no reply yet"
  attr :send_update?, :boolean, default: false, doc: "whether anyone is on the activity"
  attr :send_attendance?, :boolean, default: false, doc: "whether anyone has scanned"
  attr :delete_confirm, :any, default: false, doc: "Delete's confirm dialog, or false for none"

  # Every record's sidebar ends the same way: Actions. Custom fields are a tab (#705).
  def sidebar_end(assigns) do
    # A team admin's actions read or write the activity in D4H, which no longer has a
    # deleted one. A Records team has no D4H to open.
    assigns =
      assign(assigns,
        admin_actions?: assigns.team_admin? and !assigns.activity.deleted_at,
        d4h?: !D4H.records?(assigns.activity.team)
      )

    ~H"""
    <dl>
      <dt :if={@admin_actions? or @d4h?}>Actions</dt>
      <dd :if={@admin_actions? or @d4h?}>
        <ul id="activity-actions" class="action-list">
          <li :if={@admin_actions?}>
            <.a
              id="activity-edit"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/edit"}
            >Change activity</.a>
          </li>
          <li :if={@change_fields?}>
            <.a
              id="activity-actions-change-fields"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/fields/edit"}
            >Change fields</.a>
          </li>
          <%!-- D4H refuses tags on a published activity (#358). --%>
          <li :if={@admin_actions? and Activity.locked?(@activity)}>
            <div id="activity-tags-locked" class="hint">
              Published, so unpublish it to change its tags.
            </div>
          </li>
          <li :if={@admin_actions? and !Activity.locked?(@activity)}>
            <.a
              id="activity-change-tags"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/tags"}
            >Change tags</.a>
          </li>
          <li :if={@admin_actions?}>
            <.a
              id="activity-apply-template"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/templates"}
            >Apply a template</.a>
          </li>
          <li :if={@admin_actions? and @send_reminders?}>
            <.a
              id="activity-send-reminders"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/reminders"}
            >Send reminders</.a>
          </li>
          <li :if={@admin_actions? and @send_update?}>
            <.a
              id="activity-send-update"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/updates"}
            >Send an update</.a>
          </li>
          <%!-- It sends Take attendance's scans, so with none it has nothing to send (#766). --%>
          <li :if={@admin_actions? and @send_attendance?}>
            <.a
              id="activity-send-attendance"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/attendance"}
            >Send attendance</.a>
          </li>
          <li :if={@d4h?}>
            <.a
              id="activity-d4h"
              external={true}
              href={D4H.activity_url(@activity.team, @activity)}
            >Open in {D4H.service_name(@activity.team)}</.a>
          </li>
          <li :if={@delete_confirm}>
            <.a
              id="activity-delete"
              href="#"
              phx-click="delete"
              phx-disable-with="Deleting…"
              {@delete_confirm}
            >Delete activity</.a>
          </li>
        </ul>
      </dd>
    </dl>
    """
  end

  attr :activity, :map, required: true
  attr :hours_tags, :map, required: true
  attr :map, :map, default: nil

  # Overview: the tags, the map, and the description.
  def main_content(assigns) do
    ~H"""
    <div>
      <div class="mb-4"><.activity_tags activity={@activity} hours_tags={@hours_tags} /></div>

      <div :if={@map} class="mb-4">
        <.activity_map id="activity-map" map={@map} label="Map of activity" />
      </div>

      <div class="mb-4">
        <.markdown content={@activity.description} />
      </div>
    </div>
    """
  end

  attr :activity, :map, required: true
  attr :usages, :list, required: true
  attr :team_admin?, :boolean, default: false

  def equipment_section(assigns) do
    ~H"""
    <section id="activity-equipment">
      <p :if={@team_admin? and !@activity.deleted_at} class="action">
        <.a
          id="activity-equipment-add"
          navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/equipment/add"}
        >Add equipment</.a>
      </p>
      <.table
        :if={@usages != []}
        id="activity-equipment-table"
        rows={@usages}
        row_id={&"usage-#{&1.id}"}
        class="table-striped w-fit"
      >
        <:col :let={usage} label="Item">
          <.item_cell item={usage.equipment_item} team={@activity.team} link={@team_admin?} />
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
    |> ChoreEvent.put_chore_minutes()
    |> Repo.preload(:team)
  end

  defp format_activity_duration(activity) do
    activity.started_at
    |> Service.Convert.duration_to_minutes(activity.finished_at)
    |> Service.Format.duration()
  end
end
