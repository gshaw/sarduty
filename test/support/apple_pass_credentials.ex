defmodule App.ApplePassCredentials do
  @moduledoc "A throwaway self-signed certificate for signing passes in tests."

  def generate do
    dir = Path.join(System.tmp_dir!(), "apple-pass-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    key = Path.join(dir, "key.pem")
    cert = Path.join(dir, "cert.pem")

    {_, 0} =
      System.cmd(
        "openssl",
        ~w(req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=test -keyout #{key} -out #{cert}),
        stderr_to_stdout: true,
        env: Service.ApplePass.without_environment()
      )

    credentials = %{certificate: File.read!(cert), private_key: File.read!(key)}
    File.rm_rf!(dir)
    credentials
  end

  @doc "Turns on Apple Wallet passes with a throwaway certificate until the test exits."
  def configure do
    config =
      Map.merge(generate(), %{pass_type_id: "pass.com.sarduty.member-card", team_id: "TEAM123"})

    Application.put_env(:sarduty, :apple_pass, Map.to_list(config))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:sarduty, :apple_pass, []) end)
  end
end
