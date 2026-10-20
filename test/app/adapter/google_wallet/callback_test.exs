defmodule App.Adapter.GoogleWallet.CallbackTest do
  use ExUnit.Case, async: true

  alias App.Adapter.GoogleWallet.Callback
  alias App.GoogleWalletCredentials

  @now ~U[2026-10-20 19:00:00Z]
  @issuer GoogleWalletCredentials.issuer_id()

  setup do
    {root, root_public} = GoogleWalletCredentials.callback_key()
    json = %{"keys" => [%{"protocolVersion" => "ECv2SigningOnly", "keyValue" => root_public}]}
    %{root: root, keys: Callback.root_keys(json, @now)}
  end

  defp message(overrides \\ %{}) do
    Map.merge(
      %{
        "classId" => "#{@issuer}.sarduty.com-member-card",
        "objectId" => "#{@issuer}.sarduty.com-card-7",
        "eventType" => "save",
        "expTimeMillis" => DateTime.to_unix(@now, :millisecond) + 60_000,
        "nonce" => "n1"
      },
      overrides
    )
  end

  test "a save and a delete signed through a root key", %{root: root, keys: keys} do
    body = GoogleWalletCredentials.callback_body(root, message())

    assert Callback.verify(body, keys, @issuer, @now) ==
             {:ok,
              %{
                event: :save,
                object_id: "#{@issuer}.sarduty.com-card-7",
                class_id: "#{@issuer}.sarduty.com-member-card"
              }}

    body = GoogleWalletCredentials.callback_body(root, message(%{"eventType" => "del"}))
    assert {:ok, %{event: :delete}} = Callback.verify(body, keys, @issuer, @now)
  end

  test "an intermediate key from another root is refused", %{keys: keys} do
    {stranger, _public} = GoogleWalletCredentials.callback_key()
    body = GoogleWalletCredentials.callback_body(stranger, message())
    assert Callback.verify(body, keys, @issuer, @now) == {:error, :bad_intermediate_signature}
  end

  test "a message for another issuer, or changed after signing, is refused",
       %{root: root, keys: keys} do
    body = GoogleWalletCredentials.callback_body(root, message(), issuer: "3388000000000000002")
    assert Callback.verify(body, keys, @issuer, @now) == {:error, :bad_signature}

    body = GoogleWalletCredentials.callback_body(root, message())
    changed = Map.update!(body, "signedMessage", &String.replace(&1, "card-7", "card-8"))
    assert Callback.verify(changed, keys, @issuer, @now) == {:error, :bad_signature}
  end

  test "an expired intermediate key or message is refused", %{root: root, keys: keys} do
    past = DateTime.to_unix(@now, :millisecond) - 1

    body = GoogleWalletCredentials.callback_body(root, message(), key_expires_ms: past)
    assert Callback.verify(body, keys, @issuer, @now) == {:error, :intermediate_key_expired}

    body = GoogleWalletCredentials.callback_body(root, message(%{"expTimeMillis" => past}))
    assert Callback.verify(body, keys, @issuer, @now) == {:error, :message_expired}
  end

  test "anything else is malformed", %{root: root, keys: keys} do
    assert Callback.verify(%{}, keys, @issuer, @now) == {:error, :malformed}

    body = GoogleWalletCredentials.callback_body(root, message(%{"eventType" => "other"}))
    assert Callback.verify(body, keys, @issuer, @now) == {:error, :malformed}
  end

  test "root keys skip other protocols, expired keys, and keys that do not parse" do
    {_root, public} = GoogleWalletCredentials.callback_key()
    past = "#{DateTime.to_unix(@now, :millisecond) - 1}"

    keys = %{
      "keys" => [
        %{"protocolVersion" => "ECv1", "keyValue" => public},
        %{"protocolVersion" => "ECv2SigningOnly", "keyValue" => public, "keyExpiration" => past},
        %{"protocolVersion" => "ECv2SigningOnly", "keyValue" => "not a key"}
      ]
    }

    assert Callback.root_keys(keys, @now) == []
  end
end
