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
    test_pid = self()

    # The page reads nothing from D4H; a read would show here.
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      send(test_pid, {:d4h_read, conn.request_path})
      Req.Test.json(conn, %{})
    end)

    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  # The page, once anything it loads after showing is done, so it can't outlive the test.
  defp open(conn, path) do
    {:ok, lv, _html} = live(conn, path)
    render_async(lv)
    lv
  end

  # An activity the member attended, from `started_at` for `minutes`.
  defp attend(team, member, title, kind, started_at, minutes) do
    finished_at = DateTime.add(started_at, minutes * 60)

    activity =
      activity_fixture(team, %{
        title: title,
        activity_kind: kind,
        started_at: started_at,
        finished_at: finished_at
      })

    attendance_fixture(activity, member, %{
      started_at: started_at,
      finished_at: finished_at,
      duration_in_minutes: minutes
    })
  end

  describe "Your membership" do
    test "is the member's own page in the team's space", %{conn: conn, team: team, member: member} do
      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "h1", member.name)
      assert has_element?(lv, "#nav-area", team.name)
      assert has_element?(lv, "#side-nav-me[aria-current=page]", "Your membership")
      refute has_element?(lv, "#side-nav-members")
      assert has_element?(lv, ~s{#member-photo[src="/teams/#{team.subdomain}/me/image"]})
    end

    test "a new member's page explains each part", %{conn: conn, team: team} do
      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#no-activities", "No activities yet")
      refute has_element?(lv, "#year-stats")
      assert has_element?(lv, "#no-qualifications", "No qualifications yet")
      assert has_element?(lv, "#no-milestones", "No milestones yet")
      refute has_element?(lv, "#all-activities")
      assert has_element?(lv, "#no-card")
      refute has_element?(lv, "#letter")
    end

    test "the 10 latest activities from any year, and a link to the latest one's year",
         %{conn: conn, team: team, member: member} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for n <- 1..11 do
        started_at = DateTime.add(now, -n * 40, :day)
        attend(team, member, "Training #{n}", "exercise", started_at, 60)
      end

      lv = open(conn, ~p"/teams/#{team}/me")
      year = now |> DateTime.add(-40, :day) |> Service.YearRange.year_in(team.timezone)

      assert has_element?(lv, "h2", "Latest activities")
      assert has_element?(lv, "#activities-list", "Training 1")
      assert has_element?(lv, "#activities-list", "Training 10")
      refute has_element?(lv, "#activities-list", "Training 11")

      assert has_element?(
               lv,
               ~s{#all-activities[href="/teams/#{team.subdomain}/me/activities?year=#{year}"]},
               "All your activities"
             )
    end

    test "the last 12 months as activities, incidents, and hours",
         %{conn: conn, team: team, member: member} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      attend(team, member, "Missing hiker", "incident", DateTime.add(now, -60, :day), 180)
      attend(team, member, "Rope night", "exercise", DateTime.add(now, -30, :day), 120)
      attend(team, member, "Last year's training", "exercise", DateTime.add(now, -400, :day), 60)

      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#year-stats", "The last 12 months")
      assert has_element?(lv, "#stat-activities", "2")
      assert has_element?(lv, "#stat-incidents", "1")
      assert has_element?(lv, "#stat-hours", "5")
      assert has_element?(lv, "#activities-list", "Last year's training")
    end

    test "qualifications soonest first, with the days left on one expiring soon",
         %{conn: conn, team: team, member: member} do
      first_aid = qualification_fixture(team, %{title: "First Aid"})
      ends_at = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
      qualification_award_fixture(first_aid, member, %{ends_at: ends_at})

      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#qualifications-list-#{first_aid.id} .badge", "30 days")
    end

    test "the ID card, with Wallet buttons and the verify link",
         %{conn: conn, team: team, member: member} do
      App.ApplePassCredentials.configure()
      team = team |> Ecto.Changeset.change(id_cards_enabled: true) |> Repo.update!()

      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#no-card", "Ask one for yours")

      card = member_card_fixture(member)
      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#id-card", "a current member of #{team.name}")
      assert has_element?(lv, "#card-verify-link", MemberCard.format_code(card.code))

      assert has_element?(
               lv,
               ~s{#apple-pass[href="/teams/#{team.subdomain}/me/card/apple-wallet"]}
             )
    end

    test "the latest tax credit letter, to download", %{conn: conn, team: team, member: member} do
      tax_credit_letter_fixture(member, %{year: 2024})

      letter =
        tax_credit_letter_fixture(member, %{
          year: 2025,
          primary_minutes: 147 * 60,
          secondary_minutes: 25 * 60
        })

      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#letter h2", "2025 tax credit letter")
      # Its hours are on the year page, so they aren't read as the last 12 months'.
      refute has_element?(lv, "#letter dd")

      assert has_element?(
               lv,
               ~s{#letter-download[href="/teams/#{team.subdomain}/me/tax-credit-letters/#{letter.id}/pdf"]}
             )
    end

    test "contact details, with no emergency contact, so the page never reads D4H",
         %{conn: conn, team: team, member: member} do
      member
      |> Ecto.Changeset.change(phone: "604-555-0188", address: "2140 Fern Street")
      |> Repo.update!()

      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#contact-mobile", "604-555-0188")
      assert has_element?(lv, "#contact-address", "2140 Fern Street")
      refute has_element?(lv, "#contact-emergency")
      refute_received {:d4h_read, _path}
      assert has_element?(lv, ~s{#change-details[href="/teams/#{team.subdomain}/me/details"]})
    end

    test "the 5 latest milestones", %{conn: conn, team: team, member: member} do
      member
      |> Ecto.Changeset.change(
        joined_at:
          DateTime.utc_now() |> DateTime.add(-16 * 366, :day) |> DateTime.truncate(:second)
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

      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#milestones-list-hours-100", "Long search")
      assert has_element?(lv, "#milestones-list-incidents-1", "First incident")
      assert has_element?(lv, "#milestones-list-years-15")
      refute has_element?(lv, "#milestones-list-years-1")

      # The last 30 days' are new; the 15 years came about a year ago.
      assert has_element?(lv, "#milestones-list-hours-100.is-new")
      refute has_element?(lv, "#milestones-list-years-15.is-new")
    end

    test "the member's own photo, or a 404 so the page shows initials",
         %{conn: conn, team: team} do
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))
      conn = get(conn, ~p"/teams/#{team}/me/image")
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "image/png"

      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))
      assert conn |> recycle() |> get(~p"/teams/#{team}/me/image") |> response(404)
    end
  end

  describe "who reaches it" do
    test "a member reaches no team admin page", %{conn: conn, team: team, member: member} do
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

      lv = open(log_in_user(conn, manager), ~p"/teams/#{team}/me")
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
