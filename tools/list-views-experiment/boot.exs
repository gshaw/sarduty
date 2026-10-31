# Experiment (#768 list views). Usage, from the repo root:
#   sqlite3 db/sarduty_dev.db ".backup /tmp/x/dev.db"
#   LIST_VIEWS_DB=/tmp/x/dev.db mise exec -- mix run --no-start tools/list-views-experiment/activities.exs
# Starts only the repo, on a copy of the dev database, so nothing syncs or sends.
db = System.fetch_env!("LIST_VIEWS_DB")
repo = Application.get_env(:sarduty, App.Repo)
Application.put_env(:sarduty, App.Repo, Keyword.merge(repo, database: db, pool_size: 2))
Logger.configure(level: :warning)
{:ok, _} = Application.ensure_all_started([:tzdata, :ecto_sql, :exqlite])
{:ok, _} = App.Repo.start_link()
{:ok, _} = App.Vault.start_link()
Code.require_file("tools/list-views-experiment/list_spec.ex")
Code.require_file("tools/list-views-experiment/check.ex")
