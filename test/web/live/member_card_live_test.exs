defmodule Web.MemberCardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.IssueMemberCard
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    %{conn: log_in_user(conn, user), user: user, team: team, member: member}
  end

  test "a member's first card gets their Wallet serial, and cards made before keep theirs",
       %{team: team, member: member} do
    {:ok, first} = IssueMemberCard.call(team, member, DateTime.utc_now())
    assert first.serial_number == "member-#{member.id}"

    other = member_fixture(team)
    member_card_fixture(other, %{serial_number: "member-card-5"})
    {:ok, replacement} = IssueMemberCard.call(team, other, DateTime.utc_now())
    assert replacement.serial_number == "member-card-5"
  end

  test "issues a card", %{conn: conn, team: team, member: member} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    assert has_element?(lv, "#no-card")

    lv |> element("#issue") |> render_click()

    card = MemberCard.find_current(team, member)
    assert has_element?(lv, "#card-code", MemberCard.format_code(card.code))

    url = "#{Web.VerifyHost.url()}/#{MemberCard.format_code(card.code)}"
    assert has_element?(lv, ~s(#card-verify-link[href="#{url}"]))
  end

  test "a retired member gets no card, and an old one shows not active",
       %{conn: conn, team: team} do
    member = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    assert has_element?(lv, "#no-card", "is retired")
    refute has_element?(lv, "#issue")
    render_click(lv, "issue", %{})
    assert MemberCard.find_current(team, member) == nil

    member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    assert has_element?(lv, "#card-status", "Not active")
    assert has_element?(lv, "#revoke")
    refute has_element?(lv, "#email-pass")
  end

  test "endorsements: a link to pick them until the team shows some, then the member's",
       %{conn: conn, team: team, member: member} do
    member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    assert has_element?(lv, "#card-qualifications a", "Select endorsements to show")

    endorsement_fixture(team, %{on_card: true})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    assert has_element?(lv, "#card-qualifications", "None")
    refute has_element?(lv, "#card-qualifications a")
  end

  test "a team without ID cards sees why, and no way to issue one", %{
    conn: conn,
    team: team,
    member: member
  } do
    team |> Ecto.Changeset.change(id_cards_enabled: false) |> Repo.update!()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    assert has_element?(lv, "#id-cards-off")
    refute has_element?(lv, "#issue")
    render_click(lv, "issue", %{})
    assert MemberCard.find_current(team, member) == nil
  end

  # A pass goes on the member's phone, from Your membership, never the team admin's.
  test "offers no Wallet buttons", %{conn: conn, team: team, member: member} do
    App.ApplePassCredentials.configure()
    App.GoogleWalletCredentials.configure()
    member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    assert has_element?(lv, "#email-pass")
    refute has_element?(lv, "#apple-pass")
    refute has_element?(lv, "#google-pass")
  end

  test "cancels a card", %{conn: conn, team: team, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    lv |> element("#revoke") |> render_click()

    assert Repo.reload!(card).revoked_at
    assert has_element?(lv, "#no-card")
    refute render(lv) =~ "Cancelled"
  end

  describe "with Apple Wallet set up" do
    setup do
      App.ApplePassCredentials.configure()
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))
      :ok
    end

    test "emails the pass to the member", %{conn: conn, team: team, member: member} do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      lv |> element("#email-pass") |> render_click()

      assert_email_sent(fn email ->
        assert email.to == [{member.name, member.email}]
        assert email.text_body =~ MemberCard.format_code(card.code)

        assert [%{filename: filename, content_type: "application/vnd.apple.pkpass"}] =
                 email.attachments

        assert filename =~ ".pkpass"
      end)

      assert render(lv) =~ "Emailed the ID card to #{member.email}"
    end

    test "offers no email button when D4H has no email", %{conn: conn, team: team} do
      member = member_fixture(team, %{email: nil})
      member_card_fixture(member)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      refute has_element?(lv, "#email-pass")
      assert has_element?(lv, "#card-delivery", "has no email. Add one in D4H")
    end

    test "says how the card reaches the member", %{conn: conn, team: team, member: member} do
      member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
      assert has_element?(lv, "#card-delivery", "Email it so #{member.name} can add it")

      team |> Ecto.Changeset.change(member_logins: true) |> Repo.update!()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
      assert has_element?(lv, "#card-delivery", "adds it to Wallet from Your membership")
    end
  end

  describe "a card's phones" do
    setup %{member: member} do
      App.ApplePassCredentials.configure()
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))
      %{card: member_card_fixture(member, %{authentication_token: "token-0123456789abcdef"})}
    end

    test "a card in no Wallet says so", %{
      conn: conn,
      team: team,
      member: member
    } do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      assert has_element?(lv, "#card-phones", "Not in Wallet yet")
    end

    test "shows the phones and the last fetch, and ticks over when a phone fetches",
         %{conn: conn, team: team, member: member, card: card} do
      PassRegistration.register!(card, "device-1", "push-token-1")
      PassRegistration.register!(card, "device-2", "push-token-2")
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
      assert has_element?(lv, "#card-phones", "In Apple Wallet on 2 phones")
      refute render(lv) =~ "last downloaded"

      MemberCard.record_pass_fetched!(card, ~U[2026-09-30 22:42:00.000000Z])

      assert has_element?(
               lv,
               "#card-phones",
               "In Apple Wallet on 2 phones · last downloaded Sep 30, 15:42"
             )
    end
  end

  describe "with Google Wallet set up" do
    setup do
      App.GoogleWalletCredentials.configure()
      App.GoogleWalletCredentials.stub(self())
      :ok
    end

    test "says when the card is in Google Wallet", %{conn: conn, team: team, member: member} do
      card = member_card_fixture(member)
      MemberCard.mark_in_wallet!(card, DateTime.utc_now())
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      assert has_element?(lv, "#card-phones", "In Google Wallet")
    end

    test "emails the Google Wallet link", %{conn: conn, team: team, member: member} do
      member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      lv |> element("#email-pass") |> render_click()

      assert_email_sent(fn email ->
        assert email.text_body =~ "https://pay.google.com/gp/v/save/"
        refute email.text_body =~ "iPhone"
        assert email.attachments == []
      end)
    end
  end
end
