defmodule App.Operation.CheckGoogleWalletSaveTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.MemberCard
  alias App.Operation.CheckGoogleWalletSave

  @now ~U[2026-11-07 20:00:00.000000Z]

  setup do
    App.GoogleWalletCredentials.configure()
    %{card: member_card_fixture(member_fixture(team_fixture()))}
  end

  # Google: a token, then the object with hasUsers as given, or a 404.
  defp google(object) do
    Req.Test.stub(App.Adapter.GoogleWallet, fn conn ->
      cond do
        conn.host == "oauth2.googleapis.com" -> Req.Test.json(conn, %{"access_token" => "t"})
        object == :missing -> Plug.Conn.send_resp(conn, 404, "")
        true -> Req.Test.json(conn, object)
      end
    end)
  end

  test "a saved pass marks the card in Wallet", %{card: card} do
    google(%{"hasUsers" => true})
    assert CheckGoogleWalletSave.call(card, @now) == :saved
    assert card |> Repo.reload!() |> MemberCard.in_wallet?()
  end

  test "a pass nobody saved, or Google doesn't have, leaves the card as it was", %{card: card} do
    google(%{"hasUsers" => false})
    assert CheckGoogleWalletSave.call(card, @now) == :not_saved

    google(:missing)
    assert CheckGoogleWalletSave.call(card, @now) == :not_saved
    refute Repo.reload!(card).in_wallet_at
  end

  test "never clears a mark, since hasUsers may outlast a delete", %{card: card} do
    card = MemberCard.mark_in_wallet!(card, @now)
    google(%{"hasUsers" => false})
    assert CheckGoogleWalletSave.call(card, @now) == :not_saved
    assert Repo.reload!(card).in_wallet_at
  end
end
