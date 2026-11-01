defmodule Web.ReportLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Operation.SaveReport
  alias App.Report.BuiltIn

  test "Reports lists the built-in reports, and each opens", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports")

    for report <- BuiltIn.all() do
      assert has_element?(lv, "#report-#{report.slug}", report.name)
    end

    assert has_element?(lv, "#report-hours-by-member", "Attendance")

    lv |> element("#report-hours-by-member a") |> render_click()
    assert_redirect(lv, ~p"/teams/#{team}/reports/hours-by-member")
  end

  test "the counts show all, built-in, or the team's own, and the columns sort", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, mine} =
      SaveReport.call(team, user, nil, %{
        "name" => "Aardvark list",
        "query" => "select title from groups"
      })

    conn = log_in_user(conn, user)
    total = length(BuiltIn.all()) + 1

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports")
    assert has_element?(lv, "#report-view-all", "#{total}")
    assert has_element?(lv, "tbody#reports tr:first-child", "Aardvark list")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports?show=team")
    assert has_element?(lv, "#report-#{mine.id}")
    refute has_element?(lv, "#report-hours-by-member")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports?show=built-in")
    refute has_element?(lv, "#report-#{mine.id}")
    assert has_element?(lv, "#report-hours-by-member", "SAR Duty")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports?sort=shows")
    assert has_element?(lv, "tbody#reports tr:first-child", "Activities")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports?sort=date-")
    assert has_element?(lv, "tbody#reports tr:first-child", "Aardvark list")
  end

  test "Your team's with none says how to make one", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports?show=team")
    assert has_element?(lv, "#reports-empty")
  end

  test "every built-in report opens on a new team", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)

    for report <- BuiltIn.all() do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.slug}")
      assert has_element?(lv, "#report-count"), report.slug
      refute has_element?(lv, "#report-error"), report.slug
    end
  end

  test "Hours by member shows members' hours by kind, for the year picked", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    avery = member_fixture(team, %{name: "Avery Chen"})

    exercise =
      activity_fixture(team, %{activity_kind: "exercise", started_at: ~U[2025-03-01 18:00:00Z]})

    attendance_fixture(exercise, avery, %{duration_in_minutes: 150})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/hours-by-member?year=2025")

    assert has_element?(lv, "#report-rows-0", "Avery Chen")
    assert has_element?(lv, "#report-rows-0", "2h 30m")
    assert has_element?(lv, "#report-rows-total", "Total")
    assert has_element?(lv, "#report-count", "1 member")
    assert has_element?(lv, "#report-csv[href$='/reports/hours-by-member/csv?year=2025']")

    lv |> form("#report-values", values: %{year: "#{Date.utc_today().year}"}) |> render_change()
    assert_patch(lv, ~p"/teams/#{team}/reports/hours-by-member?year=#{Date.utc_today().year}")
    assert has_element?(lv, "#report-empty")
  end

  test "a report for fixing rows says where the fix happens", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/activities-with-no-hours-tag")

    assert has_element?(lv, "#report-fix", "Set each one's hours tag in D4H.")
  end

  test "a report that isn't one is not found", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    assert_raise Web.Status.NotFound, fn ->
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/nothing")
    end
  end
end
