# Code under test logs warnings on purpose (failed syncs, rate limits). Keep them for
# the failure report instead of between the dots. CI prints a line per test module so
# GitHub's log shows progress; locally it's dots.
formatter = if System.get_env("CI"), do: App.LineFormatter, else: ExUnit.CLIFormatter
ExUnit.start(capture_log: true, formatters: [formatter])
Ecto.Adapters.SQL.Sandbox.mode(App.Repo, :manual)

# Each test's frozen time, by its pid (App.Clock.freeze/1).
:ets.new(Service.Clock, [:named_table, :public, :set])

# Team logos go to a scratch directory, never the developer's own.
System.put_env("TEAM_LOGO_PATH", Path.join(System.tmp_dir!(), "sarduty-test-logos"))

# The file store's scratch folder is this run's own, and goes when the run ends.
file_store_dir = Application.fetch_env!(:sarduty, App.Adapter.FileStore)[:dir]
ExUnit.after_suite(fn _result -> File.rm_rf!(file_store_dir) end)

# Wallets start off whatever keys the developer's environment holds; a test that needs one
# turns it on with App.ApplePassCredentials or App.GoogleWalletCredentials.
Application.put_env(:sarduty, :apple_pass, [])
Application.put_env(:sarduty, :google_wallet, [])
