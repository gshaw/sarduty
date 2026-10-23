defmodule Web.ActivityLive do
  use Web, {:live_view_app_layout, access: :team}

  import Ecto.Query
  import Web.Components.ActivityMap
  import Web.Components.CopyButton
  import Web.Components.OpenInMaps

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Model.EquipmentUsage
  alias App.Repo
  alias Web.Components.ActivityMap

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  # Members open it too (#406), read only: the same activity, facts, and people a team
  # admin sees. Team admins also get its history, actions, and the links to member and
  # equipment pages. A member never gets an activity D4H has deleted; a team admin sees it
  # under a banner.
  def handle_params(params, _uri, socket) do
    %{current_team: team, team_admin?: team_admin?} = socket.assigns
    activity = fetch_activity(team, params["id"])

    if activity.deleted_at && !team_admin?, do: raise(Web.Status.NotFound)

    attendances = fetch_attendances(activity)

    socket =
      assign(socket,
        page_title: activity.title,
        activity: activity,
        coming?: DateTime.after?(activity.started_at, DateTime.utc_now()),
        hours_tags: Activity.hours_tags(team),
        attendances: attendances,
        attendance_count: length(attendances),
        usages: EquipmentUsage.for_activity(activity),
        map: build_map(activity)
      )

    {:noreply, socket}
  end

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
      title={"Deleted in #{D4H.service_name(@activity.team)}"}
    >
      <p>
        SAR Duty saw it was gone on {Service.Format.date_long(
          @activity.deleted_at,
          @activity.team.timezone
        )}.
      </p>
    </.banner>
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
        <.main_content
          activity={@activity}
          hours_tags={@hours_tags}
          map={@map}
          attendances={@attendances}
          attendance_count={@attendance_count}
          coming?={@coming?}
          team_admin?={@team_admin?}
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
  attr :team_admin?, :boolean, default: true

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
            <.a external={true} href={D4H.activity_url(@activity.team, @activity)}>Open D4H activity</.a>
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
          <li :if={D4H.records?(@activity.team)}>
            <.a
              id="activity-edit"
              navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/edit"}
            >Change or delete</.a>
          </li>
          <%!-- D4H refuses tags on a published activity (#358). --%>
          <li :if={!D4H.records?(@activity.team) and D4H.tags_locked?(@activity.team, @activity)}>
            <div id="activity-tags-in-d4h" class="hint">
              Change its tags in D4H. D4H does not let SAR Duty change a published activity's tags.
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
            <.a navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/take-attendance"}>Take attendance</.a>
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
  attr :attendances, :list, required: true
  attr :attendance_count, :integer, required: true
  attr :coming?, :boolean, required: true
  attr :team_admin?, :boolean, default: true

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

      <section id="activity-people">
        <h2 class="heading">
          {if @coming?, do: "Signed up", else: "Attended"} · {Service.Format.number(@attendance_count)}
        </h2>
        <p :if={@attendances == []} class="hint">
          {if @coming?, do: "Nobody has signed up yet.", else: "Nobody attended."}
        </p>
        <.activity_attendance_table
          :if={@attendances != []}
          activity={@activity}
          attendances={@attendances}
          team_admin?={@team_admin?}
        />
      </section>
    </div>
    """
  end

  attr :activity, :map, required: true
  attr :usages, :list, required: true
  attr :team_admin?, :boolean, default: true

  def equipment_section(assigns) do
    ~H"""
    <section id="activity-equipment" class="mt-8">
      <div class="heading-row">
        <h2 class="heading">Equipment · {length(@usages)}</h2>
        <.button
          :if={@team_admin? and !@activity.deleted_at}
          id="activity-equipment-add"
          size={:sm}
          navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/equipment"}
        >
          Add equipment
        </.button>
      </div>
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

  attr :activity, :map, required: true
  attr :attendances, :list, required: true
  attr :team_admin?, :boolean, default: true

  def activity_attendance_table(assigns) do
    ~H"""
    <.table id="attendance_collection" rows={@attendances} class="table-striped w-fit">
      <:col :let={record} label="ID" class="w-px">
        {record.member.ref_id}
      </:col>
      <:col :let={record} label="Name">
        <.a
          :if={@team_admin?}
          navigate={
            ~p"/teams/#{@activity.team}/members/#{record.member.id}?when=#{Calendar.strftime(@activity.started_at, "%Y")}"
          }
        >{record.member.name}</.a>
        <span :if={!@team_admin?}>{record.member.name}</span>
      </:col>
      <:col :let={record} label="Start" align="right" class="whitespace-nowrap">
        {Service.Format.datetime_short(
          record.started_at,
          @activity.team.timezone
        )}
      </:col>
      <:col :let={record} label="Finish" align="right" class="whitespace-nowrap">
        {Service.Format.time_short(
          record.finished_at,
          @activity.team.timezone
        )}
      </:col>
      <:col :let={record} label="Duration" align="right" class="whitespace-nowrap">
        {Service.Format.duration(record.duration_in_minutes)}
      </:col>
    </.table>
    """
  end

  @doc "Sends a page that calls D4H back to a deleted activity's page."
  def leave_deleted(socket, activity) do
    socket
    |> put_flash(
      :error,
      "This activity is deleted in #{D4H.service_name(socket.assigns.current_team)}. Nothing can be sent to it."
    )
    |> push_navigate(to: ~p"/teams/#{socket.assigns.current_team}/activities/#{activity.id}")
  end

  def fetch_activity(team, activity_id) do
    team
    |> Activity.find!(activity_id)
    |> Repo.preload(:team)
  end

  def fetch_attendances(activity) do
    activity
    |> Ecto.assoc(:attendances)
    |> where([a], a.status == "attending")
    |> join(:inner, [a], m in assoc(a, :member))
    |> order_by([a, m], asc: m.name)
    |> preload(:member)
    |> Repo.all()
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
