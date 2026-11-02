# Charts as reports experiment

An experiment, not for merge. It asks whether every chart on the site could be a
report: a query, then a `chart` line that draws its rows. If so, a chart on the
Dashboard opens its report, and a team admin copies it to make their own.

Branch `chart-reports-experiment` starts from the head of the open report stack (PRs 820
to 823), so the format clause and Coast Range SAR are in. Each change to the app is
marked `Experiment (charts)`:

- `App.Report.Chart` reads the last line of a report's text, `chart <kind> [compare year]
[cumulative]`, and shapes the rows into what `Web.Components.Chart` draws. The engine
  never sees the line: pages hand it the text above it.
- Four date functions in `App.Report.Expr`: `date()`, `months_since()`, `day_of_week()`,
  and `hour()`. And `sum(condition)`, which counts the rows where it holds, for a stat's
  second number.
- `App.Report.Context` has `dates_now` and `dates_today`, the moment a query's own dates
  read. `compare year` sets them a year back; fields' rules, such as Attended, still read
  `now`. `App.Report.run/5` and `run_with/3` take them.
- `Web.Components.ReportChart` draws the chart above a report's rows, on its page and in
  the editor's preview. Built-in reports gain the Dashboard's charts.

```sh
mkdir -p /tmp/chart-exp && sqlite3 db/sarduty_dev.db ".backup /tmp/chart-exp/dev.db"
export CHART_DB=/tmp/chart-exp/dev.db
mise exec -- mix run --no-start tools/chart-reports-experiment/dashboard.exs
mise exec -- mix run --no-start tools/chart-reports-experiment/member_year.exs
mise exec -- mix run --no-start tools/chart-reports-experiment/timing.exs
mise exec -- mix run --no-start tools/chart-reports-experiment/new_charts.exs
```

Run on 2026-11-02 against a copy of the sanitized dev database (7 teams):

| Script            | What it compares                                          | Checks         |
| ----------------- | --------------------------------------------------------- | -------------- |
| `dashboard.exs`   | Every stat, line, and chart but the map, 7 teams, 6 times | 620 of 630     |
| `member_year.exs` | A member's year page, 15 members a team, 2024 to 2026     | 1,500 of 1,500 |

The 10 Dashboard differences are the Dashboard's, not the reports': on Dec 31 after a
leap year it loads 730 days and misses Jan 1 of last year (6 checks), and it counts a
member's hours on an activity that hasn't started when their row started days before it
(4 checks).

`specs/` holds the reports: `dashboard/` and `member/` are compared with the pages,
`new/` are charts no page draws, run for their shape and time.
