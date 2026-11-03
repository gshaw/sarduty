defmodule Web.ActivityMileageLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Operation.BuildMileageReport
  alias Service.Format

  # Each attended row's round trip from home to the activity and to the yard (#230), from
  # SAR Duty's copy. The Mapbox lookups are saved, so only the first visit, or one after
  # an address or a location changes, waits for Mapbox.
  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    activity = Activity.find!(team, params["id"])

    if Activity.deleted?(activity),
      do: {:noreply, Web.ActivityLive.leave_deleted(socket, activity)},
      else: {:noreply, load(socket, team, activity)}
  end

  defp load(socket, team, activity) do
    socket =
      assign(socket,
        page_title: "#{activity.title} · Mileage report",
        activity: activity,
        yard: Coordinate.build(team.lat, team.lng)
      )

    if activity.coordinate do
      assign_async(socket, :mileage_report, fn ->
        {:ok, %{mileage_report: BuildMileageReport.call(team, activity, DateTime.utc_now())}}
      end)
    else
      assign(socket, mileage_report: nil)
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        label={"#{@activity.ref_id}"}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label="Mileage report" />
    </.breadcrumbs>

    <h1 class="title">{@activity.title}</h1>
    <%= if @activity.coordinate do %>
      <dl>
        <dt>Activity latitude and longitude</dt>
        <dd>{Format.coordinate(Coordinate.build(@activity.coordinate), 5)}</dd>
        <dt>Yard latitude and longitude</dt>
        <dd :if={@yard}>{Format.coordinate(@yard, 5)}</dd>
        <dd :if={!@yard} id="no-yard">None. Refresh the team in Team settings.</dd>
      </dl>
    <% else %>
      <%!-- A Records team's activity form takes an address, not a location, so a Records
           team has nowhere to add one. --%>
      <p id="no-location">
        The mileage report is not available. The activity has no latitude and longitude.
        <span :if={!D4H.records?(@current_team)}>Add its location in {@service}.</span>
      </p>
    <% end %>

    <.async_result :let={report} :if={@mileage_report} assign={@mileage_report}>
      <:loading>
        <.spinner>Working out driving distances…</.spinner>
      </:loading>
      <:failed>
        <p id="report-error">The mileage report did not load. Reload the page to try again.</p>
      </:failed>

      <p :if={report.yard_to_activity_km} id="yard-to-activity">
        Yard to activity round trip: {Format.km(report.yard_to_activity_km)}
      </p>
      <p :if={report.rows == []} id="mileage-nobody">Nobody attended.</p>

      <.table
        :if={report.rows != []}
        id="mileage_report"
        rows={report.rows}
        row_id={&"mileage-row-#{&1.attendance.id}"}
        class="table-striped"
      >
        <:col :let={row} label="Member">
          <.member_cell member={row.member} team={@current_team} />
          <span :if={row.two_rows?} class="hint block">
            {Format.month_day(row.attendance.started_at, @current_team.timezone)}
          </span>
        </:col>
        <:col :let={row} align="right" label="To activity">
          {row.activity_km && Format.km(row.activity_km)}
        </:col>
        <:col :let={row} align="right" label="To yard">
          {row.yard_km && Format.km(row.yard_km)}
        </:col>
        <:col :let={row} label="Home address">
          {row.member.address}
          <span :if={is_atom(row.home)} class="hint block">{home_text(row.home, @service)}</span>
        </:col>
      </.table>
      <p class="mt-4">
        Distances are round trips by car, from each member's home to the activity and to
        the yard. A member on two days has a row for each.
      </p>
      <p>
        <.a
          external={true}
          href="https://docs.mapbox.com/playground/geocoding/"
          phx-no-format
        >Mapbox Geocoder</.a> finds each home. <.a
          external={true}
          href="https://docs.mapbox.com/playground/directions/"
          phx-no-format
        >Mapbox Directions</.a> works out the distances. Both are saved, so a changed address is
        looked up again.
      </p>
    </.async_result>
    """
  end

  defp home_text(:no_address, service), do: "No home address in #{service}."
  defp home_text(:not_found, _service), do: "Mapbox couldn't find this address."
  defp home_text(:unknown, _service), do: "Mapbox didn't answer. Reload the page to try again."
end
