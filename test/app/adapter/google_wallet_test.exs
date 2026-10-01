defmodule App.Adapter.GoogleWalletTest do
  use ExUnit.Case, async: true

  alias App.Adapter.GoogleWallet

  @now ~U[2026-09-30 12:00:00Z]

  test "the save link is a JWT signed with the service account's key, naming only the object" do
    credentials = App.GoogleWalletCredentials.generate()
    url = GoogleWallet.save_url("3388.card-7", credentials, @now)

    assert "https://pay.google.com/gp/v/save/" <> jwt = url
    [header, claims, signature] = String.split(jwt, ".")

    assert %{"alg" => "RS256"} = decode(header)

    assert %{
             "aud" => "google",
             "typ" => "savetowallet",
             "iss" => "wallet@example.iam.gserviceaccount.com",
             "payload" => %{"genericObjects" => [%{"id" => "3388.card-7"}]}
           } = decode(claims)

    [entry] = :public_key.pem_decode(credentials["private_key"])

    {:RSAPrivateKey, _, modulus, exponent, _, _, _, _, _, _, _} =
      :public_key.pem_entry_decode(entry)

    assert :public_key.verify(
             header <> "." <> claims,
             :sha256,
             Base.url_decode64!(signature, padding: false),
             {:RSAPublicKey, modulus, exponent}
           )
  end

  test "upsert replaces the object, and creates it when Google has none" do
    test_pid = self()

    Req.Test.stub(App.Adapter.GoogleWallet, fn conn ->
      send(test_pid, {conn.method, conn.request_path})
      status = if conn.method == "PUT", do: 404, else: 200
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{})
    end)

    assert :ok = GoogleWallet.upsert("token", "genericObject", %{id: "3388.card-7"})
    assert_received {"PUT", "/walletobjects/v1/genericObject/3388.card-7"}
    assert_received {"POST", "/walletobjects/v1/genericObject"}
  end

  defp decode(part), do: part |> Base.url_decode64!(padding: false) |> Jason.decode!()
end
