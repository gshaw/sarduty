defmodule Web.CardLinkLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
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

    assert has_element?(
             lv,
             "#card-link-intro",
             "a current member of Coast Range SAR, with your endorsements"
           )

    assert has_element?(
             lv,
             ~s{#card-link-wallets-apple[href="#{path}/apple-wallet"] img[alt="Add to Apple Wallet"]}
           )

    assert has_element?(
             lv,
             ~s{#card-link-wallets-google[href="#{path}/google-wallet"] img[alt="Add to Google Wallet"]}
           )

    assert has_element?(lv, "#open-on-phone .qr-code svg")
    assert has_element?(lv, "#open-on-phone", "Scan the code with your phone's camera")
  end

  test "In Wallet says what SAR Duty knows, and changes while the page is open",
       %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, CardLinks.path(card))
    assert has_element?(lv, "#card-link-apple-status", "Not in Apple Wallet yet")
    assert has_element?(lv, "#card-link-google-status", "Not in Google Wallet yet")

    # A phone registering the pass, and Google saying it was saved, each broadcast.
    PassRegistration.register!(card, "device-1", "push-token-1")
    assert has_element?(lv, "#card-link-apple-status", "In Apple Wallet on 1 phone")

    MemberCard.mark_in_wallet!(card, DateTime.utc_now())
    assert has_element?(lv, "#card-link-google-status", "In Google Wallet")
  end

  test "a tap on Apple's badge waits for the phone, until it registers the pass",
       %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, CardLinks.path(card))

    lv |> element("#card-link-wallets-apple") |> render_click()

    assert has_element?(
             lv,
             "#card-link-waiting",
             "Waiting for your phone to add it to Apple Wallet"
           )

    refute has_element?(lv, "#card-link-wallets")

    PassRegistration.register!(card, "device-1", "push-token-1")
    refute has_element?(lv, "#card-link-waiting")
    assert has_element?(lv, "#card-link-wallets")
    assert has_element?(lv, "#card-link-apple-status", "In Apple Wallet on 1 phone")
  end

  test "Cancel brings the badges back, and so does giving up after a while",
       %{conn: conn, member: member} do
    {:ok, lv, _html} = live(conn, member |> member_card_fixture() |> CardLinks.path())

    lv |> element("#card-link-wallets-google") |> render_click()
    assert has_element?(lv, "#card-link-waiting", "Opening Google Wallet")
    lv |> element("#card-link-cancel") |> render_click()
    assert has_element?(lv, "#card-link-wallets")

    lv |> element("#card-link-wallets-apple") |> render_click()
    %{waiting_ref: ref} = :sys.get_state(lv.pid).socket.assigns
    send(lv.pid, {:give_up, ref})
    assert has_element?(lv, "#card-link-wallets")
    assert has_element?(lv, "#card-link-not-yet", "Your phone hasn't added it yet")
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
    refute has_element?(lv, "#card-link-wallets-apple")
    refute has_element?(lv, "#card-link-wallets-google")
    refute has_element?(lv, "#open-on-phone")
  end
end
