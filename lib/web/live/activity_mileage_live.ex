defmodule Web.ActivityMileageLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Coordinate

  alias App.Operation.BuildMilesageReport

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Mileage Report")}
  end

  def handle_params(params, _uri, socket) do
    activity = Activity.get(params["id"])
    d4h = D4H.build_context(socket.assigns.current_user)
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
      <:item label="Activities" path={~p"/#{@current_team.subdomain}/activities"} />
      <:item
        label={"##{@activity.ref_id}"}
        path={~p"/#{@current_team.subdomain}/activities/#{@activity.id}"}
      />
      <:item label="Mileage Report" />
    </.breadcrumbs>

    <h1 class="title mb-p"><%= @activity.title %></h1>
    <%= if @activity.coordinate do %>
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
      <p>Mileage report not available because activity does not have a location coordinate.</p>
    <% end %>

    <%= if @mileage_report do %>
      <.async_result :let={report} assign={@mileage_report}>
        <:loading>
          <.spinner>Loading mileage report...</.spinner>
        </:loading>
        <:failed :let={_reason}>There was an error loading the mileage report</:failed>

        <p>
          Yard to Activity Round Trip: <%= report.yard_to_activity_km %> km <%= report.yard_to_activity_hours %> hours
        </p>

        <.table id="mileage_report" rows={report.attendees} class="table-striped">
          <:header_row>
            <th></th>
            <th colspan="2">To Activity</th>
            <th colspan="2">To Yard</th>
            <th colspan="2"></th>
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
          Address coordinate is geocoded using <.a
            external={true}
            href="https://docs.mapbox.com/playground/geocoding/"
            phx-no-format
          >Mapbox Geocoder</.a>.

          Distances and durations calculated with <.a
            external={true}
            href="https://docs.mapbox.com/playground/directions/"
            phx-no-format
          >Mapbox Directions</.a>.
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
        d4h_activity_id = socket.assigns.activity.d4h_activity_id
        report = BuildMilesageReport.call(d4h, d4h_activity_id)
        {:ok, %{mileage_report: report}}
      end)

    {:noreply, socket}
  end
end
