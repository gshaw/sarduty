defmodule App.GoogleWalletCredentials do
  @moduledoc "A throwaway service account key for signing Google Wallet requests in tests."

  @issuer_id "3388000000000000001"

  def generate do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])
    %{"client_email" => "wallet@example.iam.gserviceaccount.com", "private_key" => pem}
  end

  def issuer_id, do: @issuer_id

  @doc "Turns on Google Wallet passes with a throwaway key until the test exits."
  def configure do
    Application.put_env(:sarduty, :google_wallet,
      issuer_id: @issuer_id,
      service_account: Jason.encode!(generate())
    )

    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:sarduty, :google_wallet, []) end)
  end

  @doc "Stubs Google: a token, then 200 for every class and object, each sent to the test."
  def stub(test_pid) do
    Req.Test.stub(App.Adapter.GoogleWallet, fn conn ->
      if conn.host == "oauth2.googleapis.com" do
        Req.Test.json(conn, %{"access_token" => "access-token"})
      else
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:google, conn.method, conn.request_path, Jason.decode!(body)})
        Req.Test.json(conn, %{})
      end
    end)
  end
end
