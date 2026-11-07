defmodule Web.CardLinkLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias Web.CardLinks

  setup do
    App.ApplePassCredentials.configure()
    App.GoogleWalletCredentials.configure()
    team = team_fixture(%{name: "Coast Range SAR"})
    member = member_fixture(team, %{name: "Cameron Ruiz"})
    %{team: team, member: member}
  end

  test "a live, active card offers both Wallets, and Open on your phone", %{
    conn: conn,
    member: member
  } do
    path = member |> member_card_fixture() |> CardLinks.path()
    {:ok, lv, _html} = live(conn, path)

    assert has_element?(lv, "#card-link-team", "Coast Range SAR")
    assert has_element?(lv, "#card-link-intro", "Cameron Ruiz, your ID card shows you are")

    assert has_element?(
             lv,
             ~s{#card-link-apple[href="#{path}/apple-wallet"] img[alt="Add to Apple Wallet"]}
           )

    assert has_element?(
             lv,
             ~s{#card-link-google[href="#{path}/google-wallet"] img[alt="Add to Google Wallet"]}
           )

    assert has_element?(lv, "#open-on-phone .qr-code svg")
    assert has_element?(lv, "#open-on-phone", "Scan the code with your phone's camera")
  end

  test "the page is kept out of search", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    conn = get(conn, CardLinks.path(card))
    assert get_resp_header(conn, "x-robots-tag") == ["noindex"]
  end

  test "a replaced card says so and offers nothing", %{conn: conn, member: member} do
    old = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})
    member_card_fixture(member)

    {:ok, lv, _html} = live(conn, CardLinks.path(old))

    assert has_element?(lv, "#card-link-replaced", "Use the link in your newest email.")
    refute_offers(lv)
  end

  test "a cancelled card says so and offers nothing", %{conn: conn, member: member} do
    card = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})
    {:ok, lv, _html} = live(conn, CardLinks.path(card))

    assert has_element?(lv, "#card-link-cancelled", "This ID card was cancelled.")
    refute_offers(lv)
  end

  test "a card that is not active says so and offers nothing", %{conn: conn, team: team} do
    retired = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    card = member_card_fixture(retired)
    {:ok, lv, _html} = live(conn, CardLinks.path(card))

    assert has_element?(lv, "#card-link-inactive", "This ID card is not active.")
    refute_offers(lv)
  end

  test "a bad token is not found", %{conn: conn} do
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/cards/not-a-token") end
  end

  defp refute_offers(lv) do
    refute has_element?(lv, "#card-link-wallets")
    refute has_element?(lv, "#card-link-apple")
    refute has_element?(lv, "#card-link-google")
    refute has_element?(lv, "#open-on-phone")
  end
end
