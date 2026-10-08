defmodule Web.ActivityLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.ActivityMap

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Repo
  alias Web.Components.ActivityMap

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    activity = fetch_activity(socket.assigns.current_team, params["id"])
    attendances = fetch_attendances(activity)

    socket =
      assign(socket,
        page_title: activity.title,
        activity: activity,
        attendances: attendances,
        attendance_count: length(attendances),
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
    <.breadcrumbs team={@current_team}>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item label={"#{@activity.ref_id}"} />
    </.breadcrumbs>

    <h1 class="title">{@activity.title}</h1>
    <.banner :if={@activity.deleted_at} id="deleted-in-d4h" kind={:danger} title="Deleted in D4H">
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
          attendances={@attendances}
          attendance_count={@attendance_count}
        />
      </aside>
      <main class="content-2/3">
        <.main_content
          activity={@activity}
          map={@map}
          attendances={@attendances}
          attendance_count={@attendance_count}
        />
      </main>
    </div>
    """
  end

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

      <div :if={hours_type = activity_hours_type(@activity)}>
        <dt>SARVAC hours</dt>
        <dd>{hours_type}</dd>
      </div>

      <div :if={@activity.address}>
        <dt>Address</dt>
        <dd>{@activity.address}</dd>
      </div>
      <div :if={@activity.coordinate && @activity.coordinate != Activity.null_island()}>
        <dt>Latitude and longitude</dt>
        <dd>
          {@activity.coordinate}
        </dd>
      </div>

      <dt>History</dt>
      <dd>
        <.a
          id="activity-history-link"
          navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/history"}
        >
          Changes to this activity
        </.a>
      </dd>

      <%!-- Each action reads or writes the activity in D4H, which no longer has it. --%>
      <dt :if={!@activity.deleted_at}>Actions</dt>
      <dd :if={!@activity.deleted_at}>
        <ul id="activity-actions" class="action-list">
          <li :if={!D4H.hosted?(@activity.team)}>
            <.a external={true} href={D4H.activity_url(@activity.team, @activity)}>
              Open D4H activity
            </.a>
          </li>
          <li>
            <.a navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/take-attendance"}>
              Take attendance
            </.a>
          </li>
          <li>
            <.a navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/attendance"}>
              Import attendance
            </.a>
          </li>
          <li>
            <.a navigate={~p"/teams/#{@activity.team}/activities/#{@activity.id}/mileage"}>
              Mileage report
            </.a>
          </li>
        </ul>
      </dd>
    </dl>
    """
  end

  def main_content(assigns) do
    ~H"""
    <div>
      <div class="mb-4"><.activity_tags activity={@activity} /></div>

      <div :if={@map} class="measure mb-4">
        <.activity_map id="activity-map" map={@map} label="Map of activity" />
      </div>

      <div class="mb-4">
        <.markdown content={@activity.description} />
      </div>

      <div :if={@attendance_count > 0}>
        <.activity_attendance_table activity={@activity} attendances={@attendances} />
      </div>
    </div>
    """
  end

  def activity_attendance_table(assigns) do
    ~H"""
    <.table id="attendance_collection" rows={@attendances} class="table-striped w-fit">
      <:col :let={record} label="ID" class="w-px">
        {record.member.ref_id}
      </:col>
      <:col :let={record} label="Name">
        <.a navigate={
          ~p"/teams/#{@activity.team}/members/#{record.member.id}?when=#{Calendar.strftime(@activity.started_at, "%Y")}"
        }>
          {record.member.name}
        </.a>
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
        {Service.Format.duration_as_hours_minutes_short(record.duration_in_minutes)}
      </:col>
    </.table>
    """
  end

  @doc "Sends a page that calls D4H back to a deleted activity's page."
  def leave_deleted(socket, activity) do
    socket
    |> put_flash(:error, "This activity is deleted in D4H. Nothing can be sent to it.")
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
    |> Service.Format.duration_as_hours_minutes_medium()
  end

  defp format_total_effort(attendances) do
    total_minutes =
      attendances
      |> Enum.map(& &1.duration_in_minutes)
      |> Enum.sum()

    rounded_minutes =
      if total_minutes > 300, do: round(total_minutes / 60) * 60, else: total_minutes

    Service.Format.duration_as_hours_minutes_medium(rounded_minutes)
  end
end
