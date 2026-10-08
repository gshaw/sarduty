defmodule Web.TeamDashboardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team

  defp open(conn, user, team), do: conn |> log_in_user(user) |> live(~p"/teams/#{team}")

  defp hours_from_now(hours),
    do: DateTime.utc_now() |> DateTime.add(hours, :hour) |> DateTime.truncate(:second)

  defp at(hours, attrs) do
    started_at = hours_from_now(hours)
    Map.merge(%{started_at: started_at, finished_at: DateTime.add(started_at, 2, :hour)}, attrs)
  end

  test "renders team dashboard", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} = open(conn, user, team)

    assert html =~ team.name
  end

  test "shows the team logo only once one is saved", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = open(conn, user, team)
    refute has_element?(lv, "#team-logo")

    team_logo_fixture(team)

    {:ok, lv, _html} = open(conn, user, team)
    assert has_element?(lv, "#team-logo")
  end

  test "a failed refresh needs attention and says why", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, team} =
      Team.update(team, %{
        d4h_refresh_result: "Error: No D4H access key. Save one in team settings."
      })

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#attention-refresh", "No D4H access key. Save one in team settings.")
  end

  test "the refresh line keeps its links while a refresh runs", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = open(conn, user, team)
    assert has_element?(lv, "#d4h-updated")
    assert has_element?(lv, "#refresh-now:not([disabled])")

    {:ok, team} = Team.update(team, %{d4h_refresh_result: "Refreshing"})
    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#refreshing", "Refreshing from D4H…")
    assert has_element?(lv, "#refresh-now[disabled]")
  end

  test "an empty team has nothing coming up and nothing to do", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = open(conn, user, team)

    refute has_element?(lv, "#next-up")
    assert has_element?(lv, "#coming-up-empty")
    assert has_element?(lv, "#needs-attention-empty")
  end

  test "the activity starting soon is NextUp, with the page's take attendance button",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    soon = activity_fixture(team, at(3, %{title: "Rope rescue"}))
    later = activity_fixture(team, at(72, %{title: "Night navigation"}))
    activity_fixture(team, at(24 * 20, %{title: "Too far off"}))
    activity_fixture(team_fixture(), at(2, %{title: "Another team's"}))

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#next-up", "Rope rescue")

    assert has_element?(
             lv,
             ~s{#next-up-take-attendance[href="/teams/#{team.subdomain}/activities/#{soon.id}/take-attendance"]}
           )

    assert has_element?(lv, "#coming-up-#{later.id}", "Take attendance")
    refute has_element?(lv, "#coming-up-#{soon.id}")
    refute has_element?(lv, "#coming-up-list", "Too far off")
    refute has_element?(lv, "#next-up", "Another team's")
  end

  test "this team's drafts and members missing details need attention", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, at(-48, %{is_published: false}))
    activity_fixture(team, at(-48, %{is_published: true}))
    # Drafts from before the last 30 days are left alone.
    activity_fixture(team, at(-24 * 40, %{is_published: false}))
    member_fixture(team, %{phone: nil})
    member_fixture(team, %{email: nil})
    member_fixture(team, %{phone: nil, left_at: ~U[2025-01-01 00:00:00Z]})
    member_fixture(team, %{phone: nil, email: nil, not_a_person: true})

    other = team_fixture()
    activity_fixture(other, at(-48, %{is_published: false}))
    member_fixture(other, %{email: nil})

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#attention-drafts", "1 draft activity")

    assert has_element?(
             lv,
             ~s{#attention-drafts a[href="/teams/#{team.subdomain}/activities?status=draft&when=recent&sort=date-"]}
           )

    assert has_element?(
             lv,
             "#attention-missing_details",
             "2 members have no email or mobile phone"
           )

    assert has_element?(
             lv,
             ~s{#attention-missing_details a[href="/teams/#{team.subdomain}/members?details=missing"]}
           )
  end

  test "Check activities lists the same drafts the dashboard counts", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, at(-48, %{title: "Counted draft", is_published: false}))
    activity_fixture(team, at(-24 * 40, %{title: "Old draft", is_published: false}))
    activity_fixture(team, at(-1, %{title: "Running draft", is_published: false}))
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
    assert has_element?(lv, "#attention-drafts", "1 draft activity")

    {:ok, list, _html} =
      lv |> element("#attention-drafts a") |> render_click() |> follow_redirect(conn)

    assert has_element?(list, "#activity_collection", "Counted draft")
    refute has_element?(list, "#activity_collection", "Old draft")
    refute has_element?(list, "#activity_collection", "Running draft")
  end

  test "a qualification running out needs attention", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team)

    qualification_award_fixture(qualification, member_fixture(team), %{
      ends_at: hours_from_now(24 * 10)
    })

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#attention-expiring", "1 qualification expires within 60 days")
  end

  test "the team's year loads after the rest of the page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, at(-24 * 5, %{activity_kind: "incident"}))

    {:ok, lv, _html} = open(conn, user, team)

    assert render_async(lv) =~ "Activities by month"
    assert has_element?(lv, "#stat-incidents", "1")
    assert has_element?(lv, "#activity-calendar")
  end
end
