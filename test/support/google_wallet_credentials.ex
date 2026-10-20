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

  # cspell:ignore secp -- secp256r1 is OTP's name for the P-256 curve
  @doc "A P-256 key pair as `{private, public}`, the public one as Google's base64 DER."
  def callback_key do
    {:ECPrivateKey, _version, _private, {:namedCurve, curve}, point, _attrs} =
      private = :public_key.generate_key({:namedCurve, :secp256r1})

    {:SubjectPublicKeyInfo, der, _} =
      :public_key.pem_entry_encode(
        :SubjectPublicKeyInfo,
        {{:ECPoint, point}, {:namedCurve, curve}}
      )

    {private, Base.encode64(der)}
  end

  @doc """
  A callback body as Google signs it: `root` signs a fresh intermediate key, which signs
  `message` for the issuer. `key_expires_ms` is the intermediate key's expiry.
  """
  def callback_body(root, message, opts \\ []) do
    {intermediate, intermediate_public} = callback_key()
    issuer = Keyword.get(opts, :issuer, @issuer_id)
    expires = Keyword.get(opts, :key_expires_ms, 4_102_444_800_000)

    signed_key =
      Jason.encode!(%{"keyValue" => intermediate_public, "keyExpiration" => "#{expires}"})

    signed_message = Jason.encode!(message)

    %{
      "protocolVersion" => "ECv2SigningOnly",
      "intermediateSigningKey" => %{
        "signedKey" => signed_key,
        "signatures" => [sign(["GooglePayPasses", "ECv2SigningOnly", signed_key], root)]
      },
      "signedMessage" => signed_message,
      "signature" =>
        sign(["GooglePayPasses", issuer, "ECv2SigningOnly", signed_message], intermediate)
    }
  end

  defp sign(parts, key) do
    data = for part <- parts, into: <<>>, do: <<byte_size(part)::little-32, part::binary>>
    data |> :public_key.sign(:sha256, key) |> Base.encode64()
  end
end
