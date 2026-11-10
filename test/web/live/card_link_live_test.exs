defmodule Web.CardLinkLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.IssueMemberCard
  alias App.Repo
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

    assert has_element?(lv, "#card-link-title", "Your Coast Range SAR ID card")

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

  test "what a copy can't do, the card to save, Print ID card, and Verify beside it",
       %{conn: conn, team: team, member: member} do
    card = member_card_fixture(member)
    path = CardLinks.path(card)
    {:ok, lv, html} = live(conn, path)

    # On a phone, where the sidebar's QR code hides, Verify and Lost your phone follow the card.
    order =
      for id <- ~w(card-link-no-wallet card-link-card card-link-print card-link-help),
          do: elem(:binary.match(html, ~s{id="#{id}"}), 0)

    assert order == Enum.sort(order)
    assert has_element?(lv, "#card-link-help #card-link-lost", "Ask a team admin")

    assert has_element?(lv, ~s{#card-link-card img[src="#{path}/image"]})

    assert has_element?(
             lv,
             ~s{#card-link-card-save[href="#{path}/image"][download="#{team.subdomain}-id-card.png"][phx-hook="SaveImage"]},
             "Save image"
           )

    assert has_element?(lv, ~s{#card-link-print-link[href="#{path}/pdf"]}, "Print ID card")
    assert has_element?(lv, "#card-link-print", "Your endorsements show when someone verifies")

    verify = MemberCard.verify_url(card.code, Web.VerifyHost.url())
    assert has_element?(lv, ~s{#card-link-verify-link[href="#{verify}"]}, "Verify your ID card")
    assert has_element?(lv, "#card-link-no-wallet", "Show this card")
  end

  test "a line under the badges says what SAR Duty sees, and changes while the page is open",
       %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, CardLinks.path(card))
    assert has_element?(lv, "#card-link-status", "doesn't see your ID card in Wallet yet")

    # A phone registering the pass, and Google saying it was saved, each broadcast.
    PassRegistration.register!(card, "device-1", "push-token-1")
    assert has_element?(lv, "#card-link-status", "sees your ID card in Apple Wallet.")

    MemberCard.mark_in_wallet!(card, DateTime.utc_now())
    assert has_element?(lv, "#card-link-status", "in Apple Wallet and in Google Wallet.")
  end

  # iCloud carries a pass added on an iPhone to the member's iPad, which registers on its
  # own, so a count would say 2 for 1 added. The ID Card tab keeps it.
  test "the line never counts devices", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    PassRegistration.register!(card, "iphone", "push-token-1")
    PassRegistration.register!(card, "ipad", "push-token-2")
    {:ok, lv, _html} = live(conn, CardLinks.path(card))

    assert has_element?(lv, "#card-link-status", "SAR Duty sees your ID card in Apple Wallet.")
    refute has_element?(lv, "#card-link-status", "device")
  end

  # The page's assigns: which Wallet a tap started a check on, and its give-up ref.
  defp checking(lv),
    do: Map.take(:sys.get_state(lv.pid).socket.assigns, [:checking, :checking_ref])

  test "a tap on Apple's badge leaves the line as it was, until the phone registers the pass",
       %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, CardLinks.path(card))

    lv |> element("#card-link-wallets-apple") |> render_click()
    assert has_element?(lv, "#card-link-status", "doesn't see your ID card in Wallet yet")
    assert %{checking: :apple} = checking(lv)

    PassRegistration.register!(card, "device-1", "push-token-1")
    assert has_element?(lv, "#card-link-status", "in Apple Wallet.")
    assert %{checking: nil} = checking(lv)
  end

  # A Wallet that already holds the card sends no news: Apple doesn't register the pass
  # again, and Google's save is already marked.
  test "a tap on a Wallet that already holds the card starts no check",
       %{conn: conn, member: member} do
    card = member_card_fixture(member)
    PassRegistration.register!(card, "device-1", "push-token-1")
    MemberCard.mark_in_wallet!(card, DateTime.utc_now())
    {:ok, lv, _html} = live(conn, CardLinks.path(card))

    lv |> element("#card-link-wallets-apple") |> render_click()
    lv |> element("#card-link-wallets-google") |> render_click()

    assert %{checking: nil} = checking(lv)

    assert has_element?(lv, "#card-link-status", "in Apple Wallet and in Google Wallet.")
  end

  test "a replacement isn't in Wallet until a phone fetches it, though its phones held the old card",
       %{conn: conn, team: team, member: member} do
    old = member_card_fixture(member)
    PassRegistration.register!(old, "device-1", "push-token-1")
    {:ok, replacement} = IssueMemberCard.call(team, member, DateTime.utc_now())

    {:ok, lv, _html} = live(conn, CardLinks.path(replacement))
    assert has_element?(lv, "#card-link-status", "doesn't see your ID card in Wallet yet")

    lv |> element("#card-link-wallets-apple") |> render_click()
    assert %{checking: :apple} = checking(lv)
    # The phone, now holding the replacement, fetches it with its own token.
    replacement |> Repo.reload!() |> MemberCard.record_pass_fetched!(DateTime.utc_now())

    assert has_element?(lv, "#card-link-status", "in Apple Wallet.")
    assert %{checking: nil} = checking(lv)
  end

  test "Google's badge opens in a new tab, and a tap checks for a while, once",
       %{conn: conn, member: member} do
    {:ok, lv, _html} = live(conn, member |> member_card_fixture() |> CardLinks.path())
    assert has_element?(lv, ~s{#card-link-wallets-google[target="_blank"]})

    lv |> element("#card-link-wallets-google") |> render_click()
    assert has_element?(lv, "#card-link-status", "doesn't see your ID card in Wallet yet")
    assert %{checking: :google, checking_ref: ref} = checking(lv)

    # A second tap keeps the one check.
    lv |> element("#card-link-wallets-google") |> render_click()
    assert %{checking_ref: ^ref} = checking(lv)

    send(lv.pid, {:give_up, ref})
    assert %{checking: nil} = checking(lv)
    assert has_element?(lv, "#card-link-status", "doesn't see your ID card in Wallet yet")
  end

  test "while it checks Google, the page asks Google, and a save ends the check",
       %{conn: conn, member: member} do
    Req.Test.stub(App.Adapter.GoogleWallet, fn conn ->
      if conn.host == "oauth2.googleapis.com",
        do: Req.Test.json(conn, %{"access_token" => "t"}),
        else: Req.Test.json(conn, %{"hasUsers" => true})
    end)

    {:ok, lv, _html} = live(conn, member |> member_card_fixture() |> CardLinks.path())
    lv |> element("#card-link-wallets-google") |> render_click()

    send(lv.pid, :check_google)
    render_async(lv)
    assert %{checking: nil} = checking(lv)
    assert has_element?(lv, "#card-link-status", "sees your ID card in Google Wallet.")
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

    assert has_element?(
             lv,
             "#card-link-cancelled",
             "This ID card was cancelled. Ask a team admin"
           )

    refute_offers(lv)
  end

  test "a card that is not active says so and offers nothing", %{conn: conn, team: team} do
    retired = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    card = member_card_fixture(retired)
    {:ok, lv, _html} = live(conn, CardLinks.path(card))

    assert has_element?(lv, "#card-link-inactive", "This ID card is not active. Ask a team admin")
    refute_offers(lv)
  end

  describe "Your membership" do
    test "the card's own member, logged in, has a trail back to it" do
      %{team: team, member: member, user: user} = member_with_login_fixture()
      path = member |> member_card_fixture() |> CardLinks.path()

      {:ok, lv, _html} = live(log_in_user(build_conn(), user), path)

      assert has_element?(
               lv,
               ~s{.breadcrumbs a[href="/teams/#{team.subdomain}/me"]},
               "Your membership"
             )

      assert has_element?(lv, ".breadcrumbs [aria-current=page]", "ID card")
    end

    test "anyone else gets the page alone", %{conn: conn, member: member} do
      path = member |> member_card_fixture() |> CardLinks.path()
      %{user: someone_else} = member_with_login_fixture()

      for conn <- [conn, log_in_user(build_conn(), someone_else)] do
        {:ok, lv, _html} = live(conn, path)
        refute has_element?(lv, ".breadcrumbs")
        assert has_element?(lv, "#card-link-wallets")
      end
    end
  end

  test "a bad token is not found", %{conn: conn} do
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/cards/not-a-token") end
  end

  defp refute_offers(lv) do
    refute has_element?(lv, "#card-link-wallets")
    refute has_element?(lv, "#card-link-wallets-apple")
    refute has_element?(lv, "#card-link-wallets-google")
    refute has_element?(lv, "#open-on-phone")
    refute has_element?(lv, "#card-link-card")
    refute has_element?(lv, "#card-link-print")
    refute has_element?(lv, "#card-link-verify")
  end
end
