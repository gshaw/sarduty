defmodule Web.MemberCardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.MemberCard
  alias App.Operation.IssueMemberCard
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    %{conn: log_in_user(conn, user), team: team, member: member}
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
    {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members/#{member.id}/card")
    assert has_element?(lv, "#no-card")

    lv |> element("#issue") |> render_click()

    card = MemberCard.find_current(team, member)
    assert has_element?(lv, "#card-code", MemberCard.format_code(card.code))
  end

  test "replacing a card cancels the old one", %{conn: conn, team: team, member: member} do
    old = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members/#{member.id}/card")

    lv |> element("#replace") |> render_click()

    assert Repo.reload!(old).revoked_at
    new = MemberCard.find_current(team, member)
    assert new.code != old.code
    assert has_element?(lv, "#card-code", MemberCard.format_code(new.code))
  end

  test "cancels a card", %{conn: conn, team: team, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members/#{member.id}/card")

    lv |> element("#revoke") |> render_click()

    assert Repo.reload!(card).revoked_at
    assert has_element?(lv, "#no-card")
  end

  describe "with Apple Wallet set up" do
    setup do
      App.ApplePassCredentials.configure()
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, "photo-bytes"))
      :ok
    end

    test "emails the pass to the member", %{conn: conn, team: team, member: member} do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members/#{member.id}/card")

      lv |> element("#email-pass") |> render_click()

      assert_email_sent(fn email ->
        assert email.to == [{member.name, member.email}]
        assert email.text_body =~ MemberCard.format_code(card.code)

        assert [%{filename: filename, content_type: "application/vnd.apple.pkpass"}] =
                 email.attachments

        assert filename =~ ".pkpass"
      end)

      assert render(lv) =~ "Emailed the pass to #{member.email}"
    end

    test "offers no email button when D4H has no email", %{conn: conn, team: team} do
      member = member_fixture(team, %{email: nil})
      member_card_fixture(member)

      {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members/#{member.id}/card")

      refute has_element?(lv, "#email-pass")
      assert has_element?(lv, "#apple-pass")
    end
  end

  describe "with Google Wallet set up" do
    setup do
      App.GoogleWalletCredentials.configure()
      App.GoogleWalletCredentials.stub(self())
      :ok
    end

    test "offers the Google pass and no Apple one", %{conn: conn, team: team, member: member} do
      member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members/#{member.id}/card")

      assert has_element?(lv, "#google-pass")
      refute has_element?(lv, "#apple-pass")
    end

    test "emails the Google Wallet link", %{conn: conn, team: team, member: member} do
      member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members/#{member.id}/card")

      lv |> element("#email-pass") |> render_click()

      assert_email_sent(fn email ->
        assert email.text_body =~ "https://pay.google.com/gp/v/save/"
        refute email.text_body =~ "iPhone"
        assert email.attachments == []
      end)
    end
  end
end
