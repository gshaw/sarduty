ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(App.Repo, :manual)

# Team logos go to a scratch directory, never the developer's own.
System.put_env("TEAM_LOGO_PATH", Path.join(System.tmp_dir!(), "sarduty-test-logos"))

# Wallets start off whatever keys the developer's environment holds; a test that needs one
# turns it on with App.ApplePassCredentials or App.GoogleWalletCredentials.
Application.put_env(:sarduty, :apple_pass, [])
Application.put_env(:sarduty, :google_wallet, [])
