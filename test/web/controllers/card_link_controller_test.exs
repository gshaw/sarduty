defmodule Web.CardLinkControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  alias Web.CardLinks

  setup do
    App.ApplePassCredentials.configure()
    App.GoogleWalletCredentials.configure()
    App.GoogleWalletCredentials.stub(self())
    # The pass's photo and logo.
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))
    team = team_fixture()
    %{team: team, member: member_fixture(team)}
  end

  test "Add to Apple Wallet builds the card's pass", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    conn = get(conn, CardLinks.path(card) <> "/apple-wallet")

    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "application/vnd.apple.pkpass"
  end

  test "Add to Google Wallet sends the pass to Google and opens its save page",
       %{conn: conn, member: member} do
    card = member_card_fixture(member)
    conn = get(conn, CardLinks.path(card) <> "/google-wallet")

    assert "https://pay.google.com/gp/v/save/" <> _jwt = redirected_to(conn)
    assert_received {:google, "PUT", "/walletobjects/v1/genericObject/" <> _, _object}
  end

  test "a replaced card gets no pass", %{conn: conn, member: member} do
    old = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})
    member_card_fixture(member)

    assert_no_passes(conn, old)
  end

  test "a cancelled card gets no pass", %{conn: conn, member: member} do
    card = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})
    assert_no_passes(conn, card)
  end

  test "a card that is not active gets no pass", %{conn: conn, team: team} do
    retired = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    assert_no_passes(conn, member_card_fixture(retired))
  end

  test "a bad token gets no pass", %{conn: conn} do
    assert conn |> get(~p"/cards/not-a-token/apple-wallet") |> response(404)
    assert conn |> get(~p"/cards/not-a-token/google-wallet") |> response(404)
  end

  defp assert_no_passes(conn, card) do
    assert conn |> get(CardLinks.path(card) <> "/apple-wallet") |> response(404)
    assert conn |> get(CardLinks.path(card) <> "/google-wallet") |> response(404)
    refute_received {:google, _, _, _}
  end
end
