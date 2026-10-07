defmodule App.ViewData.TeamDashboardCharts do
  @moduledoc """
  Turns the dashboard's rows from `TeamDashboardViewData.chart_rows/2` into what its
  stats, charts, and map draw: the team's year. Pure: rows and `now` in, chart data out.
  """

  alias App.Model.Coordinate
  alias Service.Format
  alias Service.MapView
  alias Service.TimeBuckets
  alias Service.YearRange

  @kinds %{"incident" => :incident, "exercise" => :exercise, "event" => :event}
  @series [incident: "Incidents", exercise: "Exercises", event: "Events"]

  # Points further than this from the team's base are left off the map, so one activity
  # with a wrong place in D4H doesn't zoom the map out to the whole province.
  @map_radius_km 150

  def series, do: @series

  def shape(rows, team) do
    tz = team.timezone
    activities = Enum.map(rows.activities, &Map.update!(&1, :kind, fn kind -> @kinds[kind] end))
    a_year_ago = DateTime.shift(rows.now, year: -1)
    last_12 = Enum.filter(activities, &DateTime.after?(&1.started_at, a_year_ago))

    rows
    |> Map.merge(%{activities: activities, a_year_ago: a_year_ago})
    |> year_stats(tz)
    |> Map.merge(monthly_charts(rows, last_12, tz))
    |> Map.merge(%{
      calendar_days: calendar_days(last_12, rows.now, tz),
      map_points: map_points(last_12, team, rows.now)
    })
  end

  # The last 12 months, oldest first.
  defp monthly_charts(rows, last_12, tz) do
    months = TimeBuckets.months(rows.now, tz, 12)

    by_month =
      last_12
      |> Enum.map(&{&1.started_at, &1.kind})
      |> TimeBuckets.count_by_month(months, tz)

    %{
      activity_columns: activity_columns(by_month),
      monthly_activities: Enum.map(by_month, fn {_m, counts} -> Enum.sum(Map.values(counts)) end),
      monthly_incidents: Enum.map(by_month, fn {_m, counts} -> Map.get(counts, :incident, 0) end),
      monthly_hours: monthly_hours(rows.attendance, months, tz)
    }
  end

  # This year to date, beside the same days of last year.
  defp year_stats(rows, tz) do
    {this_ytd, last_ytd} = to_date(rows.activities, rows, tz)
    {attended_this_ytd, attended_last_ytd} = to_date(rows.attendance, rows, tz)

    %{
      year: rows.year,
      activities_ytd: length(this_ytd),
      activities_last_ytd: length(last_ytd),
      incidents_ytd: count_incidents(this_ytd),
      incidents_last_ytd: count_incidents(last_ytd),
      minutes_ytd: sum_minutes(attended_this_ytd),
      minutes_last_ytd: sum_minutes(attended_last_ytd),
      members: length(rows.members),
      members_joined: Enum.count(rows.members, &joined_in?(&1, rows.year, tz))
    }
  end

  # Rows from this year so far, and rows from last year up to the same day.
  defp to_date(rows, data, tz) do
    this_ytd = Enum.filter(rows, &(YearRange.year_in(&1.started_at, tz) == data.year))

    last_ytd =
      Enum.filter(rows, fn row ->
        YearRange.year_in(row.started_at, tz) == data.year - 1 and
          not DateTime.after?(row.started_at, data.a_year_ago)
      end)

    {this_ytd, last_ytd}
  end

  defp count_incidents(activities), do: Enum.count(activities, &(&1.kind == :incident))

  defp joined_in?(%{joined_at: nil}, _year, _tz), do: false
  defp joined_in?(member, year, tz), do: YearRange.year_in(member.joined_at, tz) == year

  defp sum_minutes(rows), do: rows |> Enum.map(& &1.minutes) |> Enum.sum()

  defp activity_columns(by_month) do
    Enum.map(by_month, fn {month, counts} ->
      lines =
        for {key, label} <- @series, n = Map.get(counts, key, 0), n > 0 do
          "#{n} #{String.downcase(label)}"
        end

      tip = Enum.join([Calendar.strftime(month, "%B %Y") | lines], "\n")
      %{label: Format.month_short(month), values: counts, tip: tip}
    end)
  end

  defp monthly_hours(attendance, months, tz) do
    totals =
      Enum.reduce(attendance, %{}, fn row, acc ->
        month =
          row.started_at
          |> DateTime.shift_zone!(tz)
          |> DateTime.to_date()
          |> Date.beginning_of_month()

        Map.update(acc, month, row.minutes, &(&1 + row.minutes))
      end)

    Enum.map(months, &div(Map.get(totals, &1, 0), 60))
  end

  defp calendar_days(activities, now, tz) do
    counts = activities |> Enum.map(& &1.started_at) |> TimeBuckets.count_by_day(tz)
    now |> TimeBuckets.days(tz, 365) |> Enum.map(&{&1, Map.get(counts, &1, 0)})
  end

  defp map_points(activities, team, now) do
    a_month_ago = DateTime.add(now, -30, :day)

    for activity <- activities,
        {lat, lng} <- [Coordinate.build(activity.coordinate)],
        {lat, lng} != {0.0, 0.0},
        near_base?(team, lat, lng) do
      %{
        lat: lat,
        lng: lng,
        kind: activity.kind,
        recent: DateTime.after?(activity.started_at, a_month_ago),
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
