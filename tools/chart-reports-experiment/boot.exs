# Experiment (charts, #768 follow-up). Usage, from the repo root:
#   mkdir -p /tmp/chart-exp && sqlite3 db/sarduty_dev.db ".backup /tmp/chart-exp/dev.db"
#   CHART_DB=/tmp/chart-exp/dev.db mise exec -- mix run --no-start tools/chart-reports-experiment/dashboard.exs
# Starts only the repo, on a copy of the dev database, so nothing syncs or sends.
db = System.fetch_env!("CHART_DB")
repo = Application.get_env(:sarduty, App.Repo)
Application.put_env(:sarduty, App.Repo, Keyword.merge(repo, database: db, pool_size: 2))
Logger.configure(level: :warning)
{:ok, _} = Application.ensure_all_started([:tzdata, :ecto_sql, :exqlite, :telemetry])
{:ok, _} = App.Repo.start_link()
{:ok, _} = App.Vault.start_link()
Code.require_file("tools/chart-reports-experiment/check.ex")
