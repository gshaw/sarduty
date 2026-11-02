# Experiment (places): the Dashboard's map from the built-in report Where the team went,
# against TeamDashboardCharts.map_points/3 on the same activities. The report covers the
# last 12 months as Activities by month does (this month and the 11 before); today's map
# covers a year back from now, so the days between are counted apart.
Code.require_file("tools/chart-reports-experiment/boot.exs")

alias App.Model.Team
alias App.Report.BuiltIn
alias App.Report.Chart
alias App.ViewData.{ReportRecords, TeamDashboardCharts, TeamDashboardViewData}

spec = "where-the-team-went" |> BuiltIn.get() |> Map.fetch!(:query) |> Chart.find()

moments =
  [DateTime.utc_now() | Enum.map(~w(2026-01-04T17:00:00Z 2026-03-09T06:30:00Z 2025-11-02T09:15:00Z 2026-07-01T06:59:00Z 2025-12-31T23:30:00Z), fn s -> elem(DateTime.from_iso8601(s), 1) end)]
  |> Enum.map(&DateTime.truncate(&1, :second))

dot = fn p -> {p.lat, p.lng, p.kind, p.recent} end
only_window = :ets.new(:w, [:public])

for team <- App.Repo.all(Team), now <- moments do
  label = "#{team.id} @ #{DateTime.to_iso8601(now)}"
  {:ok, run} = Chart.run(spec, team, %{}, now)
  records = ReportRecords.load(run.result, team, now)
  ours = run.data |> Chart.map_points(records, team, now) |> Enum.map(dot) |> Enum.sort()

  rows = TeamDashboardViewData.chart_rows(team, now)
  tz = team.timezone
  first = now |> DateTime.shift_zone!(tz) |> DateTime.to_date() |> Date.beginning_of_month() |> Date.shift(month: -11)
  start = Service.DayRange.start_of_day(first, tz)
  page = Enum.map(rows.activities, &%{&1 | kind: TeamDashboardCharts.kind(&1.kind)})
  in_window = Enum.filter(page, &(not DateTime.before?(&1.started_at, start)))
  theirs = in_window |> TeamDashboardCharts.map_points(team, now) |> Enum.map(dot) |> Enum.sort()
  Check.same("Map dots, same window", label, ours, theirs)

  # Today's map: a year back from now. Dots it has that the report's window leaves out.
  year_ago = DateTime.shift(now, year: -1)
  today = page |> Enum.filter(&DateTime.after?(&1.started_at, year_ago)) |> TeamDashboardCharts.map_points(team, now)
  :ets.insert(only_window, {label, length(today), length(today) - length(theirs)})
end

Check.summary()
{dots, extra} = :ets.tab2list(only_window) |> Enum.reduce({0, 0}, fn {_l, d, e}, {a, b} -> {a + d, b + e} end)
IO.puts("Today's map, all teams and moments: #{dots} dots; #{extra} from the days before the report's 12 months")
