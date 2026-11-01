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
      # The count, the filter bar's line for a report with a search or filters, or
      # nothing to show under tiles that count none.
      assert has_element?(lv, "#report-count, #report-filters-summary, #report-empty"),
             report.slug

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
    assert has_element?(lv, "#report-filters-summary", "1 member")
    assert has_element?(lv, "#report-csv[href$='/reports/hours-by-member/csv?year=2025']")

    lv |> form("#report-filters", values: %{year: "#{Date.utc_today().year}"}) |> render_change()
    # This year is where Year starts, so the URL leaves it out.
    assert_patch(lv, ~p"/teams/#{team}/reports/hours-by-member")
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

  describe "a report's page (#784)" do
    @rope """
    select title, started_at
    from activities
    order by started_at desc
    search title
    switch activity 'Kind'
      option incident 'Incidents' where kind = 'incident'
      option exercise 'Exercises' where kind = 'exercise'
    filter when 'When'
      each year(started_at) where year(started_at) = :when
    sort date 'Date' started_at
    page 2
    """

    setup do
      %{user: user, team: team} = user_with_team_fixture()

      for {title, kind, at} <- [
            {"Rope rescue", "exercise", ~U[2026-03-01 18:00:00Z]},
            {"Lost hiker", "incident", ~U[2026-04-01 18:00:00Z]},
            {"Swiftwater", "exercise", ~U[2025-05-01 18:00:00Z]}
          ] do
        activity_fixture(team, %{
          title: title,
          activity_kind: kind,
          started_at: at,
          finished_at: DateTime.add(at, 3600)
        })
      end

      {:ok, report} =
        SaveReport.call(team, user, nil, %{"name" => "Activities by kind", "query" => @rope})

      %{user: user, team: team, report: report}
    end

    test "draws the tiles, the search and filters, sortable headers, and pages", ctx do
      %{conn: conn, user: user, team: team, report: report} = ctx
      path = ~p"/teams/#{team}/reports/#{report.id}"
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(path)

      assert has_element?(lv, "#report-tile-all", "3")
      assert has_element?(lv, "#report-tile-exercise", "2")
      # The All tile says 3, so the line under the bar gives the page's range alone.
      assert has_element?(lv, "#report-filters-summary", "1–2 of 3")
      assert has_element?(lv, "#report-rows-0", "Lost hiker")
      assert has_element?(lv, "nav.pagination", "Page 1 of 2")
      assert has_element?(lv, "th[aria-sort=descending] a[href='#{path}?sort=date']")

      lv |> element("#report-tile-exercise") |> render_click()
      assert_patch(lv, path <> "?activity=exercise")
      assert has_element?(lv, "#report-rows-0", "Rope rescue")

      lv |> form("#report-filters", values: %{when: "2025"}) |> render_change()
      assert_patch(lv, path <> "?activity=exercise&when=2025")
      assert has_element?(lv, "#report-rows-0", "Swiftwater")
      assert has_element?(lv, "#report-csv[href$='/csv?activity=exercise&when=2025']")

      lv |> form("#report-filters", values: %{q: "nothing"}) |> render_change()
      assert has_element?(lv, "#report-empty", "Pick other values above.")
    end

    test "starts on the picks saved with the report, and the URL leaves them out", ctx do
      %{conn: conn, user: user, team: team, report: report} = ctx
      {:ok, report} = SaveReport.call(team, user, report, %{"values" => %{"when" => "2025"}})
      path = ~p"/teams/#{team}/reports/#{report.id}"
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(path)

      assert has_element?(lv, "#report-rows-0", "Swiftwater")
      assert has_element?(lv, "#report-tile-all", "1")

      lv |> form("#report-filters", values: %{when: "all"}) |> render_change()
      assert_patch(lv, path <> "?when=all")
      assert has_element?(lv, "#report-tile-all", "3")
    end

    test "several picks at once show as the switch's menu in the bar", ctx do
      %{conn: conn, user: user, team: team, report: report} = ctx
      path = ~p"/teams/#{team}/reports/#{report.id}"

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(path <> "?activity=incident,exercise")

      refute has_element?(lv, "#report-switch [aria-current]")

      assert has_element?(
               lv,
               "#report-filters select[name='values[activity]'] option[selected]",
               "Incidents or exercises"
             )

      lv |> form("#report-filters", values: %{activity: "incident"}) |> render_change()
      assert_patch(lv, path <> "?activity=incident")
      refute has_element?(lv, "#report-filters select[name='values[activity]']")
    end

    test "Download CSV gives every row the picks keep", ctx do
      %{conn: conn, user: user, team: team, report: report} = ctx

      csv =
        conn
        |> log_in_user(user)
        |> get(~p"/teams/#{team}/reports/#{report.id}/csv?activity=exercise&page=2")
        |> response(200)

      assert csv =~ "Rope rescue"
      assert csv =~ "Swiftwater"
      refute csv =~ "Lost hiker"
    end
  end
end
