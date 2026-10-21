defmodule Web.GoogleWalletControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  alias App.GoogleWalletCredentials
  alias App.Model.MemberCard
  alias App.Operation.BuildGooglePass
  alias App.Repo

  setup do
    GoogleWalletCredentials.configure()
    {root, root_public} = GoogleWalletCredentials.callback_key()

    Req.Test.stub(App.Adapter.GoogleWallet, fn conn ->
      Req.Test.json(conn, %{
        "keys" => [%{"protocolVersion" => "ECv2SigningOnly", "keyValue" => root_public}]
      })
    end)

    %{member: member} = member_with_login_fixture()
    %{root: root, card: member_card_fixture(member)}
  end

  defp message(card, event_type) do
    config = BuildGooglePass.config()

    %{
      "classId" => BuildGooglePass.pass_class(config).id,
      "objectId" => BuildGooglePass.object_id(card, config),
      "eventType" => event_type,
      "expTimeMillis" => DateTime.to_unix(DateTime.utc_now(), :millisecond) + 60_000,
      "nonce" => "n-#{event_type}"
    }
  end

  defp post_callback(conn, body), do: post(conn, ~p"/wallet/google", body)

  test "a save marks the card in Wallet, and a delete clears it",
       %{conn: conn, root: root, card: card} do
    body = GoogleWalletCredentials.callback_body(root, message(card, "save"))
    assert conn |> post_callback(body) |> response(200)
    assert %{in_wallet_at: %DateTime{}} = Repo.get!(MemberCard, card.id)

    body = GoogleWalletCredentials.callback_body(root, message(card, "del"))
    assert conn |> post_callback(body) |> response(200)
    assert %{in_wallet_at: nil} = Repo.get!(MemberCard, card.id)
  end

  test "a bad signature changes nothing and gets a 400", %{conn: conn, card: card} do
    {stranger, _public} = GoogleWalletCredentials.callback_key()
    body = GoogleWalletCredentials.callback_body(stranger, message(card, "save"))

    assert conn |> post_callback(body) |> response(400)
    assert %{in_wallet_at: nil} = Repo.get!(MemberCard, card.id)
  end

  test "another host's class or an unknown card is taken and ignored",
       %{conn: conn, root: root, card: card} do
    other_class = %{message(card, "save") | "classId" => "3388000000000000001.dev-member-card"}
    body = GoogleWalletCredentials.callback_body(root, other_class)
    assert conn |> post_callback(body) |> response(200)

    gone = %{message(card, "save") | "objectId" => "3388000000000000001.unknown-card-x"}
    body = GoogleWalletCredentials.callback_body(root, gone)
    assert conn |> post_callback(body) |> response(200)

    assert %{in_wallet_at: nil} = Repo.get!(MemberCard, card.id)
  end
end
