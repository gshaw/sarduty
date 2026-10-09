defmodule Web.MeLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
  alias App.Model.MemberCard
  alias App.Operation.SetTeamMemberLogins
  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture()
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  describe "the member's page" do
    test "gets a card when the member has none", %{conn: conn, team: team, member: member} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#no-card")

      lv |> element("#issue") |> render_click()

      card = MemberCard.find_current(team, member)
      assert has_element?(lv, "#card-code", MemberCard.format_code(card.code))
    end

    test "never replaces a card the member has", %{conn: conn, team: team, member: member} do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#card-code", MemberCard.format_code(card.code))
      refute has_element?(lv, "#issue")
      render_click(lv, "issue", %{})

      assert MemberCard.find_current(team, member).id == card.id
      refute Repo.reload!(card).revoked_at
    end

    test "lists the member's letters, newest first, and no one else's",
         %{conn: conn, team: team, member: member} do
      older = tax_credit_letter_fixture(member, %{year: 2024})
      newer = tax_credit_letter_fixture(member, %{year: 2025})
      other = tax_credit_letter_fixture(member_fixture(team), %{year: 2025})

      {:ok, lv, html} = live(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#letter-#{newer.id}", "Download 2025 letter")
      assert has_element?(lv, "#letter-#{older.id}", "Download 2024 letter")
      refute has_element?(lv, "#letter-#{other.id}")
      assert :binary.match(html, "letter-#{newer.id}") < :binary.match(html, "letter-#{older.id}")
    end

    test "says when there are no letters yet", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#no-letters")
    end

    test "shows no team sections in the top bar", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      refute has_element?(lv, "#nav-members")
      assert has_element?(lv, "#nav-me-#{team.subdomain}")
    end
  end

  describe "who reaches it" do
    test "a member reaches no team admin page", %{conn: conn, team: team, member: member} do
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}") end

      assert_raise Web.Status.NotFound, fn ->
        live(conn, ~p"/teams/#{team}/members/#{member.id}")
      end

      assert_error_sent 404, fn ->
        get(conn, ~p"/teams/#{team}/members/#{member.id}/card/apple-wallet")
      end
    end

    test "nobody reaches it once the team turns member logins off",
         %{conn: conn, team: team, user: user} do
      {:ok, _team} = SetTeamMemberLogins.call(team, false, user)
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/me") end
    end

    test "a member who left can't reach it", %{conn: conn, team: team, member: member} do
      member |> Ecto.Changeset.change(left_at: ~U[2026-01-01 00:00:00Z]) |> Repo.update!()
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/me") end
    end

    test "a member of another team can't reach it", %{conn: conn} do
      other = member_logins_team_fixture()
      member_fixture(other)
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{other}/me") end
    end

    test "a team admin gets their own page, since they're a member too", %{conn: conn} do
      %{user: manager, team: team} = user_with_team_fixture()
      team |> Ecto.Changeset.change(member_logins: true) |> Repo.update!()

      {:ok, lv, _html} = live(log_in_user(conn, manager), ~p"/teams/#{team}/me")
      assert has_element?(lv, "#no-card")
    end

    test "someone not a member there gets a 404, even an admin", %{conn: conn, team: team} do
      %{user: manager} = user_with_team_fixture()
      admin = make_admin(AccountsFixtures.user_fixture())

      for user <- [manager, admin] do
        conn = log_in_user(conn, user)
        assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/me") end
      end
    end

    test "logged out, it asks to log in", %{team: team} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), ~p"/teams/#{team}/me")
    end
  end

  describe "downloads" do
    test "the member's own letter", %{conn: conn, team: team, member: member} do
      letter = tax_credit_letter_fixture(member)
      conn = get(conn, ~p"/teams/#{team}/me/tax-credit-letters/#{letter.id}/pdf")

      assert response(conn, 200)
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/pdf"
    end

    test "another member's letter on the same team is a 404", %{conn: conn, team: team} do
      letter = tax_credit_letter_fixture(member_fixture(team))

      assert_error_sent 404, fn ->
        get(conn, ~p"/teams/#{team}/me/tax-credit-letters/#{letter.id}/pdf")
      end
    end

    test "the member's own Apple Wallet pass", %{conn: conn, team: team, member: member} do
      App.ApplePassCredentials.configure()
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))
      member_card_fixture(member)

      conn = get(conn, ~p"/teams/#{team}/me/card/apple-wallet")

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/vnd.apple.pkpass"
    end

    test "no pass without a card", %{conn: conn, team: team} do
      App.ApplePassCredentials.configure()
      assert conn |> get(~p"/teams/#{team}/me/card/apple-wallet") |> response(404)
    end
  end
end
