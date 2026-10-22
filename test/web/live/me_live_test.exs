defmodule Web.MeLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
  alias App.Model.PassRegistration
  alias App.Operation.SetTeamMemberLogins
  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture()
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  describe "the overview" do
    test "is in the team's space, with none of the team admins' pages", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#nav-area", team.name)
      assert has_element?(lv, "#side-nav-me[aria-current=page]", "Your membership")
      refute has_element?(lv, "#side-nav-members")
      refute has_element?(lv, "#team-switcher")
    end

    test "with no activities, says so in one line in place of each chart",
         %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      refute has_element?(lv, "#next-up")
      assert has_element?(lv, "p#hours-by-kind-chart", "No activities")
      assert has_element?(lv, "p#activity-map", "No activities")
      assert has_element?(lv, "#lately-empty")
      assert has_element?(lv, "#stat-activities", "0")
    end

    test "shows the next sign-up, the year's numbers, and the latest activities",
         %{conn: conn, team: team, member: member} do
      %{mid_year: mid_year, now: now, year: year} = this_year_fixture(team)

      coming =
        activity_fixture(team, %{title: "Rope practice", started_at: DateTime.add(now, 3, :day)})

      attendance_fixture(coming, member)

      incident =
        activity_fixture(team, %{
          title: "Overdue hiker",
          activity_kind: "incident",
          started_at: mid_year
        })

      attended =
        attendance_fixture(incident, member, %{
          started_at: mid_year,
          finished_at: DateTime.add(mid_year, 2 * 3600)
        })

      other = activity_fixture(team, %{title: "Not mine", started_at: mid_year})
      attendance_fixture(other, member_fixture(team), %{started_at: mid_year})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#next-up", "Rope practice")

      assert has_element?(
               lv,
               ~s{#next-up-calendar[href="/teams/#{team.subdomain}/me/activities/#{coming.id}/calendar"]}
             )

      assert has_element?(lv, "#stat-hours", "2")
      assert has_element?(lv, "#stat-incidents", "Incidents in #{year}")
      assert has_element?(lv, "#hours-by-kind-chart", "Incidents")
      assert has_element?(lv, "#lately-list-#{attended.id}", "Overdue hiker")
      refute render(lv) =~ "Not mine"
    end
  end

  describe "milestones" do
    test "the latest 3 on the overview, every one on their page",
         %{conn: conn, team: team, member: member} do
      member
      |> Ecto.Changeset.change(
        joined_at:
          DateTime.utc_now() |> DateTime.add(-6 * 366, :day) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      starts = DateTime.utc_now() |> DateTime.add(-30, :day) |> DateTime.truncate(:second)

      incident =
        activity_fixture(team, %{
          title: "Long search",
          activity_kind: "incident",
          started_at: starts
        })

      attendance_fixture(incident, member, %{
        started_at: starts,
        finished_at: DateTime.add(starts, 101 * 3600)
      })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#milestones-list-years-5", "5 years on the team")
      assert has_element?(lv, "#milestones-list-hours-100", "Long search")
      assert has_element?(lv, "#milestones-list-incidents-1", "First incident")
      refute has_element?(lv, "#milestones-list-years-1")
      assert has_element?(lv, ~s{#milestones a[href="/teams/#{team.subdomain}/me/milestones"]})

      {:ok, page, _html} = live(conn, ~p"/teams/#{team}/me/milestones")
      assert has_element?(page, "#milestones-years-1", "1 year on the team")
      assert has_element?(page, "#milestones-hours-100")
    end

    test "with none, says what comes first", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#milestones-empty")

      {:ok, page, _html} = live(conn, ~p"/teams/#{team}/me/milestones")
      assert has_element?(page, "#no-milestones")
    end
  end

  describe "for you to do" do
    test "with nothing to do, says so in one line", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#to-do-empty")
    end

    test "the ID card leaves once Apple Wallet registers it, or Google says it's saved",
         %{conn: conn, team: team, member: member} do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#to-do-card")

      card |> Ecto.Changeset.change(in_wallet_at: DateTime.utc_now()) |> Repo.update!()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      refute has_element?(lv, "#to-do-card")

      card |> Ecto.Changeset.change(in_wallet_at: nil) |> Repo.update!()
      PassRegistration.register!(card, "phone-1", "token")
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      refute has_element?(lv, "#to-do-card")
    end

    test "a new letter leaves once the member downloads it",
         %{conn: conn, team: team, member: member} do
      %{year: year} = this_year_fixture(team)
      letter = tax_credit_letter_fixture(member, %{year: year - 1})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#to-do-letter", "Your #{year - 1} tax credit letter is ready")

      conn |> get(~p"/teams/#{team}/me/tax-credit-letters/#{letter.id}/pdf") |> response(200)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
      refute has_element?(lv, "#to-do-letter")
    end

    test "a qualification expiring within 60 days", %{conn: conn, team: team, member: member} do
      first_aid = qualification_fixture(team, %{title: "First Aid"})
      ends_at = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
      qualification_award_fixture(first_aid, member, %{ends_at: ends_at})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")

      assert has_element?(
               lv,
               "#to-do-qualification-#{first_aid.id}",
               "First Aid expires in 30 days"
             )
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
      assert has_element?(lv, "#side-nav-me[aria-current=page]")
      assert has_element?(lv, "#side-nav-members")
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
    test "a calendar file for an activity the member signed up for, and no other",
         %{conn: conn, team: team, member: member} do
      starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)
      coming = activity_fixture(team, %{title: "Rope practice", started_at: starts})
      attendance_fixture(coming, member)
      not_mine = activity_fixture(team, %{started_at: starts})
      attendance_fixture(not_mine, member_fixture(team))

      conn = get(conn, ~p"/teams/#{team}/me/activities/#{coming.id}/calendar")
      assert response(conn, 200) =~ "SUMMARY:Rope practice"
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "text/calendar"

      other = get(recycle(conn), ~p"/teams/#{team}/me/activities/#{not_mine.id}/calendar")
      assert response(other, 404)
    end

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
