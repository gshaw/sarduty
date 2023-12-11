defmodule Web.ActivityMileageLive do
  use Web, :live_view_app

  import Web.WebComponents.A

  alias App.Adapter.D4H
  alias App.Adapter.Mapbox
  alias App.Model.Coordinate

  alias App.Operation.BuildMilesageReport

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    activity_id = params["id"]
    d4h = D4H.build_context(socket.assigns.current_user)
    {:ok, team} = D4H.fetch_team(d4h)
    activity = D4H.fetch_activity(d4h, activity_id)

    mapbox = Mapbox.build_context()
    map_image_url = Mapbox.build_static_map_url(mapbox, activity.coordinate)

    socket =
      assign(
        socket,
        mileage_report: nil,
        team: team,
        activity: activity,
        map_image_url: map_image_url
      )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="mb-p05 text-sm">
      <.a navigate={~p"/southfrasersar"}>South Fraser SAR</.a>
      /
      <.a navigate={~p"/southfrasersar/activities/"}>Activities</.a>
      /
      <.a navigate={~p"/southfrasersar/activities/#{@activity.activity_id}"}>
        #<%= @activity.activity_id %>
      </.a>
      /
      Mileage Report
    </div>
    <h1 class="title mb-p"><%= @activity.title %></h1>
    <%= if @activity.coordinate do %>
      <p :if={false && @map_image_url}>
        <img src={@map_image_url} width="480" height="320" alt="Map of activity" />
      </p>
      <p>
        <div>
          Activity Location: <%= App.Model.Coordinate.to_string(@activity.coordinate, 5) %>
        </div>
        <div>
          Yard Location: <%= App.Model.Coordinate.to_string(@team.coordinate, 5) %>
        </div>
      </p>
      <p :if={@mileage_report == nil || @mileage_report.loading == nil}>
        <.button phx-click="generate-report" class="btn-success">Generate Mileage Report</.button>
      </p>
    <% else %>
      <p>Mileage report not available because activity does not have a location coodinate.</p>
    <% end %>

    <%= if @mileage_report do %>
      <.async_result :let={report} assign={@mileage_report}>
        <:loading>
          <.spinner /> Loading mileage report...
        </:loading>
        <:failed :let={_reason}>There was an error loading the mileage report</:failed>

        <p>
          Yard to Activity Round Trip: <%= report.yard_to_activity_km %> km <%= report.yard_to_activity_hours %> hours
        </p>

        <.table id="mileage_report" rows={report.attendees}>
          <:header_row>
            <th></th>
            <th colspan="2" class="text-sm font-normal">To Activity</th>
            <th colspan="2" class="text-sm font-normal">To Yard</th>
            <th colspan="2" class="text-sm font-normal"></th>
          </:header_row>
          <:col :let={record} label="Name"><%= record.name %></:col>
          <:col :let={record} class="text-right" label="KMs"><%= record.activity_km %></:col>
          <:col :let={record} class="text-right" label="Hours"><%= record.activity_hours %></:col>
          <:col :let={record} class="text-right" label="KMs"><%= record.yard_km %></:col>
          <:col :let={record} class="text-right" label="Hours"><%= record.yard_hours %></:col>
          <:col :let={record} label="Home Address"><%= record.address %></:col>
          <:col :let={record} label="Coordinate">
            <%= Coordinate.to_string(record.coordinate, 3) %>
          </:col>
        </.table>
        <p class="mt-p">
          KMs and Hours are round trip driving distance and duration from home address coordinate to activity or yard coordinate.
        </p>
        <p>
          Address coordinate is geocoded using <a
            class="link"
            target="_blank"
            href="https://docs.mapbox.com/playground/geocoding/"
          >Mapbox Geocoder</a>.
          Distances and durations calculated with <a
            class="link"
            target="_blank"
            href="https://docs.mapbox.com/playground/directions/"
          >Mapbox Directions</a>.
        </p>
      </.async_result>
    <% end %>
    """
  end

  def handle_event("generate-report", _params, socket) do
    socket =
      socket
      |> assign(mileage_report: nil)
      |> assign_async(:mileage_report, fn ->
        d4h = D4H.build_context(socket.assigns.current_user)
        activity_id = socket.assigns.activity.activity_id
        report = BuildMilesageReport.call(d4h, activity_id)
        {:ok, %{mileage_report: report}}
      end)

    {:noreply, socket}
  end
end
