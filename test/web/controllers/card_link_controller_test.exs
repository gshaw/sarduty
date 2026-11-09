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

  test "the card's front and back are pictures, and Print ID card a PDF",
       %{conn: conn, team: team, member: member} do
    path = member |> member_card_fixture() |> CardLinks.path()

    for side <- ~w(front back) do
      conn = get(conn, "#{path}/#{side}")
      assert <<0x89, "PNG", _rest::binary>> = response(conn, 200)
      assert ["image/png"] = get_resp_header(conn, "content-type")

      assert get_resp_header(conn, "content-disposition") ==
               [~s(inline; filename="#{team.subdomain}-id-card-#{side}.png")]
    end

    conn = get(conn, "#{path}/pdf")
    assert "%PDF" <> _rest = response(conn, 200)
    assert ["application/pdf"] = get_resp_header(conn, "content-type")
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
    for route <- ~w(apple-wallet google-wallet front back pdf),
        do: assert(conn |> get("/cards/not-a-token/#{route}") |> response(404))
  end

  # Nor a picture of the card, nor its PDF.
  defp assert_no_passes(conn, card) do
    for route <- ~w(apple-wallet google-wallet front back pdf),
        do: assert(conn |> get(CardLinks.path(card) <> "/#{route}") |> response(404))

    refute_received {:google, _, _, _}
  end
end
