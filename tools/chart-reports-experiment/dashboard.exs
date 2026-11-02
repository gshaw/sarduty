# Experiment (charts): the Dashboard's stats and charts, from reports, against the
# Dashboard's own code (TeamDashboardViewData.chart_rows/2 + TeamDashboardCharts.shape/2),
# for every team, at several moments.
Code.require_file("tools/chart-reports-experiment/boot.exs")
alias App.Report.Chart, as: ChartSpec

alias App.Model.Team
alias App.ViewData.TeamDashboardCharts
alias App.ViewData.TeamDashboardViewData

dir = "tools/chart-reports-experiment/specs/dashboard"
spec = fn name -> ChartSpec.read(Path.join(dir, name <> ".report")) end

run! = fn name, team, now ->
  {:ok, out} = ChartSpec.run(spec.(name), team, %{}, now)
  out
end

# Today, then moments that cross a year, a month, and daylight saving time.
moments =
  [DateTime.utc_now() | Enum.map(~w(2026-01-04T17:00:00Z 2026-03-09T06:30:00Z 2025-11-02T09:15:00Z 2026-07-01T06:59:00Z 2025-12-31T23:30:00Z), fn s -> elem(DateTime.from_iso8601(s), 1) end)]
  |> Enum.map(&DateTime.truncate(&1, :second))

teams = App.Repo.all(Team)

for team <- teams, now <- moments do
  label = "#{team.id} @ #{DateTime.to_iso8601(now)}"
  page = team |> TeamDashboardViewData.chart_rows(now) |> TeamDashboardCharts.shape(team)

  # Stats (V1: one report for the number and its compare, one for its line).
  a = run!.("activities-this-year", team, now)
  Check.same("Activities stat", label, {a.data.value, a.before_data.value}, {page.activities_ytd, page.activities_last_ytd})
  Check.same("Activities line", label, hd(run!.("activities-last-12-months", team, now).data.series).values, page.monthly_activities)

  i = run!.("incidents-this-year", team, now)
  Check.same("Incidents stat", label, {i.data.value, i.before_data.value}, {page.incidents_ytd, page.incidents_last_ytd})
  Check.same("Incidents line", label, hd(run!.("incidents-last-12-months", team, now).data.series).values, page.monthly_incidents)

  h = run!.("member-hours-this-year", team, now)
  Check.same("Member hours stat", label, {h.data.value, h.before_data.value}, {page.minutes_ytd, page.minutes_last_ytd})
  hours = hd(run!.("member-hours-last-12-months", team, now).data.series).values
  Check.same("Member hours line", label, Enum.map(hours, &div(&1, 60)), page.monthly_hours)

  Check.same("Members stat", label, run!.("current-members", team, now).data.value, page.members)
  Check.same("Members joined", label, run!.("members-joined-this-year", team, now).data.value, page.members_joined)
  # One report for the tile: the number and its note, with sum(condition).
  both = run!.("current-members-and-joined", team, now).data
  Check.same("Members tile (one report)", label, {both.value, elem(both.note, 0)}, {page.members, page.members_joined})

  # V2: one report per stat, its line the same rows as its number.
  a2 = run!.("activities-this-year-by-month", team, now)
  Check.same("Activities stat (one report)", label, {a2.data.value, a2.before_data.value}, {page.activities_ytd, page.activities_last_ytd})
  i2 = run!.("incidents-this-year-by-month", team, now)
  Check.same("Incidents stat (one report)", label, {i2.data.value, i2.before_data.value}, {page.incidents_ytd, page.incidents_last_ytd})
  h2 = run!.("member-hours-this-year-by-month", team, now)
  Check.same("Member hours stat (one report)", label, {h2.data.value, h2.before_data.value}, {page.minutes_ytd, page.minutes_last_ytd})

  # Activities by month: the same 12 columns, the same count per kind in each.
  cols = run!.("activities-by-month", team, now).data
  ours = Enum.map(cols.columns, &{&1.label, Map.reject(&1.values, fn {_k, v} -> v == 0 end)})
  theirs = Enum.map(page.activity_columns, &{&1.label, Map.reject(&1.values, fn {_k, v} -> v == 0 end)})
  Check.same("Activities by month", label, ours, theirs)
  Check.same("Activities by month, kind colours", label, Enum.all?(cols.series, fn {k, _} -> k in [:incident, :exercise, :event] end), true)

  # Every day out: 365 days ending today, a count each.
  Check.same("Every day out", label, run!.("every-day-out", team, now).data.days, page.calendar_days)
end

Check.summary()
