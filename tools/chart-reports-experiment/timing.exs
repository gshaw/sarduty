# Experiment (charts): how long the Dashboard's lower half takes today, against the same
# stats and charts run as reports. Median and 90th percentile of N runs, and queries per run.
Code.require_file("tools/chart-reports-experiment/boot.exs")
alias App.Report.Chart, as: ChartSpec

import Ecto.Query, only: [where: 2]
alias App.Model.{Activity, Team}
alias App.Report.Context
alias App.ViewData.{TeamDashboardCharts, TeamDashboardViewData}

:ets.new(:q, [:named_table, :public])
:ets.insert(:q, {:n, 0})
:telemetry.attach("count", [:app, :repo, :query], fn _, _m, _, _ -> :ets.update_counter(:q, :n, 1) end, nil)

dir = "tools/chart-reports-experiment/specs/dashboard"
specs = fn names -> Enum.map(names, &ChartSpec.read(Path.join(dir, &1 <> ".report"))) end

one = specs.(~w(activities-this-year activities-last-12-months incidents-this-year incidents-last-12-months
  member-hours-this-year member-hours-last-12-months current-members members-joined-this-year
  activities-by-month every-day-out))

two = specs.(~w(activities-this-year-by-month incidents-this-year-by-month member-hours-this-year-by-month
  current-members members-joined-this-year activities-by-month every-day-out))

now = DateTime.utc_now() |> DateTime.truncate(:second)
n = String.to_integer(System.get_env("N", "20"))

measure = fn f ->
  for _ <- 1..3, do: f.()
  :ets.insert(:q, {:n, 0})
  times = for _ <- 1..n, do: elem(:timer.tc(f), 0) / 1000
  [{:n, queries}] = :ets.lookup(:q, :n)
  s = Enum.sort(times)
  "median #{Float.round(Enum.at(s, div(n, 2)), 1)} ms, p90 #{Float.round(Enum.at(s, div(n * 9, 10)), 1)} ms, #{div(queries, n)} queries"
end

teams = App.Repo.all(Team)
sizes = Map.new(teams, fn t -> {t.id, App.Repo.aggregate(where(Activity, team_id: ^t.id), :count)} end)

for team <- Enum.sort_by(teams, &(-sizes[&1.id])) |> Enum.take(3) do
  IO.puts("\nTeam #{team.id}: #{sizes[team.id]} activities")
  IO.puts("  Dashboard today (chart_rows + shape):  " <> measure.(fn -> team |> TeamDashboardViewData.chart_rows(now) |> TeamDashboardCharts.shape(team) end))
  IO.puts("  Context.new alone:                     " <> measure.(fn -> Context.new(team, now) end))
  IO.puts("  As reports, a stat and its line apart: " <> measure.(fn -> Enum.each(one, &ChartSpec.run(&1, team, %{}, now)) end))
  IO.puts("  As reports, one report per stat:       " <> measure.(fn -> Enum.each(two, &ChartSpec.run(&1, team, %{}, now)) end))
  IO.puts("  One report per stat, one Context:      " <> measure.(fn -> context = Context.new(team, now); Enum.each(two, &ChartSpec.run_with(&1, context)) end))
  for spec <- two do
    IO.puts("    #{String.pad_trailing(spec.name, 34)} " <> measure.(fn -> ChartSpec.run(spec, team, %{}, now) end))
  end
end
