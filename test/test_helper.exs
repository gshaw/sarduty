ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(App.Repo, :manual)

# Team logos go to a scratch directory, never the developer's own.
System.put_env("TEAM_LOGO_PATH", Path.join(System.tmp_dir!(), "sarduty-test-logos"))
