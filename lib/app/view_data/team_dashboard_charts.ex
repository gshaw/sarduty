defmodule App.ViewData.TeamDashboardCharts do
  @moduledoc """
  What the Dashboard's map and the year page's charts share (#826): the activity kinds'
  series and the map's rules. The Dashboard's own charts are built-in reports
  (App.Report.Chart). Pure.
  """

  alias App.Model.Coordinate
  alias Service.Format
  alias Service.MapView

  @kinds %{"incident" => :incident, "exercise" => :exercise, "event" => :event}
  @series [incident: "Incidents", exercise: "Exercises", event: "Events"]

  # Points further than this from the team's base are left off the map, so one activity
  # with a wrong place in D4H doesn't zoom the map out to the whole province.
  @map_radius_km 150

  def series, do: @series

  @doc "D4H's activity kind as the charts' series: `:incident`, `:exercise`, or `:event`."
  def kind(activity_kind), do: @kinds[activity_kind]

  @doc """
  The map's dots for activities with a place near the team's base, each with `:kind` as
  `kind/1` gives it. Large dots are the last 30 days, `LAST_N_DAYS:30` (#792). The year
  page and a report's `chart map` (#826) use it too.
  """
  def map_points(activities, team, now) do
    {a_month_ago, _tomorrow} = Service.DayRange.last(now, team.timezone, 30)

    for activity <- activities,
        {lat, lng} <- [Coordinate.build(activity.coordinate)],
        {lat, lng} != {0.0, 0.0},
        near_base?(team, lat, lng) do
      %{
        lat: lat,
        lng: lng,
        kind: activity.kind,
        recent: not DateTime.before?(activity.started_at, a_month_ago),
        tip: "#{activity.title}\n#{Format.date_long(activity.started_at, team.timezone)}"
      }
    end
  end

  defp near_base?(%{lat: base_lat, lng: base_lng}, lat, lng)
       when is_number(base_lat) and is_number(base_lng) do
    MapView.km_between({base_lat, base_lng}, {lat, lng}) <= @map_radius_km
  end

  defp near_base?(_team, _lat, _lng), do: true
end
