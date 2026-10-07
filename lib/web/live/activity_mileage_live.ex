defmodule Web.ActivityMileageLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Coordinate

  alias App.Operation.BuildMilesageReport

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Mileage report")}
  end

  def handle_params(params, _uri, socket) do
    activity = Activity.find!(socket.assigns.current_team, params["id"])

    if Activity.deleted?(activity),
      do: {:noreply, Web.ActivityLive.leave_deleted(socket, activity)},
      else: load(socket, activity)
  end

  defp load(socket, activity) do
    d4h = D4H.build_context_from_team(socket.assigns.current_team)
    {:ok, team} = D4H.fetch_team(d4h)

    socket =
      assign(
        socket,
        mileage_report: nil,
        team: team,
        activity: activity
      )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        label={"#{@activity.ref_id}"}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label="Mileage report" />
    </.breadcrumbs>

    <h1 class="title mb-p">{@activity.title}</h1>
    <%= if @activity.coordinate do %>
      <dl>
        <dt>Activity latitude and longitude</dt>
        <dd>{App.Model.Coordinate.to_string(@activity.coordinate, 5)}</dd>
        <dt>Yard latitude and longitude</dt>
        <dd>{App.Model.Coordinate.to_string(@team.coordinate, 5)}</dd>
      </dl>
      <p :if={@mileage_report == nil || @mileage_report.loading == nil}>
        <.button phx-click="generate-report" variant={:success}>Generate mileage report</.button>
      </p>
    <% else %>
      <p>
        The mileage report is not available. The activity has no latitude and longitude. Add its location in D4H.
      </p>
    <% end %>

    <%= if @mileage_report do %>
      <.async_result :let={report} assign={@mileage_report}>
        <:loading>
          <.spinner>Calculating driving distances…</.spinner>
        </:loading>
        <:failed :let={_reason}>The mileage report did not load. Generate it again.</:failed>

        <p>
          Yard to activity round trip: {report.yard_to_activity_km} km, {report.yard_to_activity_hours} hours
        </p>

        <.table id="mileage_report" rows={report.attendees} class="table-striped">
          <:header_row>
            <th></th>
            <th colspan="2">To activity</th>
            <th colspan="2">To yard</th>
            <th colspan="2"></th>
          </:header_row>
          <:col :let={record} label="Name">{record.name}</:col>
          <:col :let={record} class="text-right" label="km">{record.activity_km}</:col>
          <:col :let={record} class="text-right" label="Hours">{record.activity_hours}</:col>
          <:col :let={record} class="text-right" label="km">{record.yard_km}</:col>
          <:col :let={record} class="text-right" label="Hours">{record.yard_hours}</:col>
          <:col :let={record} label="Home address">{record.address}</:col>
          <:col :let={record} label="Latitude and longitude">
            {Coordinate.to_string(record.coordinate, 3)}
          </:col>
        </.table>
        <p class="mt-p">
          Distances and times are round trips by car, from each member's home to the activity
          and to the yard.
        </p>
        <p>
          <.a
            external={true}
            href="https://docs.mapbox.com/playground/geocoding/"
            phx-no-format
          >Mapbox Geocoder</.a> finds each home's latitude and longitude. <.a
            external={true}
            href="https://docs.mapbox.com/playground/directions/"
            phx-no-format
          >Mapbox Directions</.a> calculates the distances and durations.
        </p>
      </.async_result>
    <% end %>
    """
  end

  def handle_event("generate-report", _params, socket) do
    current_team = socket.assigns.current_team
    d4h_activity_id = socket.assigns.activity.d4h_activity_id
    activity_kind = socket.assigns.activity.activity_kind

    socket =
      socket
      |> assign(mileage_report: nil)
      |> assign_async(:mileage_report, fn ->
        d4h = D4H.build_context_from_team(current_team)
        report = BuildMilesageReport.call(d4h, d4h_activity_id, activity_kind)
        {:ok, %{mileage_report: report}}
      end)

    {:noreply, socket}
  end
end
