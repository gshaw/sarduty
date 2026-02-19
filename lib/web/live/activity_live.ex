defmodule Web.ActivityLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Adapter.Mapbox
  alias App.Model.Activity
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    activity = fetch_activity(params["id"])
    attendances = fetch_attendances(activity)

    mapbox = Mapbox.build_context()
    map_image_url = Mapbox.build_static_map_url(mapbox, activity.coordinate)

    socket =
      assign(socket,
        page_title: activity.title,
        activity: activity,
        attendances: attendances,
        attendance_count: length(attendances),
        map_image_url: map_image_url
      )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Activities" path={~p"/#{@current_team.subdomain}/activities"} />
      <:item label={"#{@activity.ref_id}"} />
    </.breadcrumbs>

    <h1 class="title">{@activity.title}</h1>
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
          map_image_url={@map_image_url}
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
          {@attendance_count} members
          · {calculate_total_duration(@attendances)}
        </dd>
      </div>

      <dt>Start</dt>
      <dd>
        {Service.Format.medium_datetime(@activity.started_at, @activity.team.timezone)}
      </dd>
      <dt>Finish</dt>
      <dd>
        {Service.Format.medium_datetime(@activity.finished_at, @activity.team.timezone)}
      </dd>
      <dt>Duration</dt>
      <dd>
        {Service.Format.minutes_to_hm(
          DateTime.diff(@activity.finished_at, @activity.started_at, :second) / 60
        )}
      </dd>

      <div :if={@activity.address}>
        <dt>Address</dt>
        <dd>{@activity.address}</dd>
      </div>
      <div :if={@activity.coordinate && @activity.coordinate != Activity.null_island()}>
        <dt>Coordinate</dt>
        <dd>
          {@activity.coordinate}
        </dd>
      </div>

      <dt>Actions</dt>
      <dd>
        <ul class="action-list">
          <li>
            <.a external={true} href={D4H.activity_url(@activity.team, @activity)}>
              Open D4H Activity
            </.a>
          </li>
          <li>
            <.a navigate={~p"/#{@activity.team.subdomain}/activities/#{@activity.id}/attendance"}>
              Import Attendance
            </.a>
          </li>
          <li>
            <.a navigate={~p"/#{@activity.team.subdomain}/activities/#{@activity.id}/mileage"}>
              Mileage Report
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
      <div class="mb-p"><.activity_tags activity={@activity} /></div>

      <div :if={@map_image_url} class="mb-p">
        <img src={@map_image_url} width="640" height="480" alt="Map of activity" />
      </div>

      <div class="mb-p">
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
    <.table id="attendance_collection" rows={@attendances} class="mt-p05 table-striped w-fit">
      <:col :let={record} label="ID" class="w-px">
        {record.member.ref_id}
      </:col>
      <:col :let={record} label="Name">
        <.a navigate={
          ~p"/#{@activity.team.subdomain}/members/#{record.member.id}?when=#{Calendar.strftime(@activity.started_at, "%Y")}"
        }>
          {record.member.name}
        </.a>
      </:col>
      <:col :let={record} label="Start" class="whitespace-nowrap">
        {Service.Format.same_day_datetime(
          record.started_at,
          @activity.started_at,
          @activity.team.timezone
        )}
      </:col>
      <:col :let={record} label="Finish" class="whitespace-nowrap">
        {Service.Format.same_day_datetime(
          record.finished_at,
          @activity.started_at,
          @activity.team.timezone
        )}
      </:col>
      <:col :let={record} label="Duration" class="whitespace-nowrap" align="right">
        {Service.Format.minutes_to_hm(record.duration_in_minutes)}
      </:col>
    </.table>
    """
  end

  def fetch_activity(activity_id) do
    activity_id
    |> Activity.get()
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

  defp calculate_total_duration(attendances) do
    total_minutes =
      attendances
      |> Enum.map(& &1.duration_in_minutes)
      |> Enum.sum()

    Service.Format.minutes_to_hm(total_minutes)
  end
end
