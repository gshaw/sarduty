defmodule Web.ReportFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.SavedReport
  alias App.Operation.SaveReport

  test "a report runs as you type, and saves once it has a name", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member_fixture(team, %{name: "Avery Chen"})
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

    assert has_element?(lv, "#report-preview-count", "runs as you type")
    assert has_element?(lv, "#field-standing")

    lv
    |> form("#report-form", report: %{query: "select title, kind from equipment"})
    |> render_change()

    assert has_element?(lv, "#field-kind")
    assert has_element?(lv, "#report-preview-count", "0 items")

    lv
    |> form("#report-form", report: %{query: "select name from members where nme = 'x'"})
    |> render_change()

    assert has_element?(lv, "#report-form", "members has no field nme. Did you mean name?")
    refute has_element?(lv, "#report-preview")

    lv
    |> form("#report-form",
      report: %{query: "select name from members order by name", name: "Everyone"}
    )
    |> render_submit()

    report = App.Repo.get_by!(SavedReport, team_id: team.id, name: "Everyone")
    assert_redirect(lv, ~p"/teams/#{team}/reports/#{report.id}")
  end

  # A new member after the rows ran shows only if typing the name ran the query again.
  test "typing the name leaves the rows as they ran", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member_fixture(team, %{name: "Avery Chen"})
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")
    query = "select name from members"

    count = fn -> lv |> element("#report-preview-count") |> render() end

    lv |> form("#report-form", report: %{query: query}) |> render_change()
    before = count.()

    member_fixture(team, %{name: "Blake Diaz"})
    lv |> form("#report-form", report: %{query: query, name: "Everyone"}) |> render_change()
    assert count.() == before

    lv |> form("#report-form", report: %{query: query <> " order by name"}) |> render_change()
    refute count.() == before
  end

  test "Save with a mistake lists it in the error summary", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

    lv
    |> form("#report-form", report: %{query: "select hour_tags from activities", name: "Tags"})
    |> render_submit()

    assert has_element?(lv, "#report-errors", "activities has no field hour_tags")
  end

  test "Copy and change starts from a built-in report", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/hours-by-member")

    lv |> element("#report-copy") |> render_click()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/new?from=hours-by-member")

    assert has_element?(lv, "#report_name[value='Hours by member (copy)']")
    assert has_element?(lv, "#report-preview-filter-year")
  end

  test "a team's report lists, opens, changes, and deletes", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, report} =
      SaveReport.call(team, user, nil, %{
        "name" => "Groups",
        "query" => "select title from groups"
      })

    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports")
    assert has_element?(lv, "#report-#{report.id}", "Groups")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}")
    assert has_element?(lv, "#report-change")
    assert has_element?(lv, "#report-query", "Made by")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}/edit")
    lv |> form("#report-form", report: %{name: "Group list"}) |> render_submit()
    assert_redirect(lv, ~p"/teams/#{team}/reports/#{report.id}")
    assert SavedReport.get(team, report.id).name == "Group list"

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}/edit")
    lv |> element("#report-delete-button") |> render_click()
    assert_redirect(lv, ~p"/teams/#{team}/reports")
    assert SavedReport.get(team, report.id) == nil
  end

  test "a built-in report cannot be changed", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    assert_raise Web.Status.NotFound, fn ->
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/hours-by-member/edit")
    end
  end

  test "another team's report is not found", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    other = team_fixture()

    {:ok, theirs} =
      SaveReport.call(other, user, nil, %{
        "name" => "Theirs",
        "query" => "select title from groups"
      })

    conn = log_in_user(conn, user)

    for path <- [
          ~p"/teams/#{team}/reports/#{theirs.id}",
          ~p"/teams/#{team}/reports/#{theirs.id}/edit"
        ] do
      assert_raise Web.Status.NotFound, fn -> live(conn, path) end
    end

    assert_raise Web.Status.NotFound, fn ->
      get(conn, ~p"/teams/#{team}/reports/#{theirs.id}/csv")
    end
  end

  describe "the page's clauses (#784)" do
    test "the preview draws them, and a tile or a menu picks", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      activity_fixture(team, %{title: "Lost hiker", activity_kind: "incident"})
      activity_fixture(team, %{title: "Rope rescue", activity_kind: "exercise"})
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

      assert has_element?(lv, "#clause-switch", "The tiles")

      query = """
      select title from activities
      order by title
      switch activity 'Kind'
        option incident 'Incidents' where kind = 'incident'
      filter status 'Status'
        option draft 'Draft' where published = false
      sort title 'Activity' title
      """

      lv |> form("#report-form", report: %{query: query}) |> render_change()
      assert has_element?(lv, "#report-preview-tile-all", "2")
      assert has_element?(lv, "#report-preview-filter-status")

      lv |> element("#report-preview-tile-incident") |> render_click()
      assert has_element?(lv, "#report-preview-count", "1 activity")
      assert has_element?(lv, "#report-preview-tile-incident[aria-current=page]")

      lv |> element("th a", "Activity") |> render_click()
      assert has_element?(lv, "th[aria-sort=descending]", "Activity")

      lv
      |> form("#report-form",
        report: %{query: query, name: "Incidents", values: %{status: "draft"}}
      )
      |> render_submit()

      report = App.Repo.get_by!(SavedReport, team_id: team.id, name: "Incidents")
      assert report.values == %{"activity" => "incident", "sort" => "title-", "status" => "draft"}
    end

    test "a mistake in an option names its line and the option", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

      query = """
      select title, started_at
      from activities
      order by started_at desc
      filter status 'Status'
        option draft 'Draft' where publshed = false
      page 50
      """

      lv |> form("#report-form", report: %{query: query}) |> render_change()

      assert has_element?(
               lv,
               "#report-form",
               "Line 5, option draft: activities has no field publshed. Did you mean published?"
             )
    end
  end
end
