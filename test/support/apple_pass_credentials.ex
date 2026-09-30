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
end
