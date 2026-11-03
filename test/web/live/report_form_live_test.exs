defmodule Web.ReportFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ReportVersion
  alias App.Model.SavedReport
  alias App.Operation.SaveReport
  alias App.Report.Draft

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

  test "an agent's link fills the form, and saving names the agent (#816)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member_fixture(team, %{name: "Avery Chen"})
    params = %{query: "select name from members", name: "Everyone", agent: "Claude"}
    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/new?#{params}")

    assert has_element?(lv, "#report-preview td", "Avery Chen")
    lv |> form("#report-form") |> render_submit()

    report = App.Repo.get_by!(SavedReport, team_id: team.id, name: "Everyone")
    assert report.query == "select name from members"
    assert report.agent == "Claude"

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/teams/#{team}/reports/#{report.id}/edit?#{%{query: "select name, position from members", agent: "Codex"}}"
      )

    lv |> form("#report-form") |> render_submit()
    report = App.Repo.reload!(report)
    assert report.query == "select name, position from members"
    assert report.agent == "Codex"

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}/edit")
    lv |> form("#report-form", report: %{name: "All of us"}) |> render_submit()
    assert App.Repo.reload!(report).agent == "Codex"
  end

  test "format draws a column another way (#804)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{timezone: "America/Vancouver"}})
    member = member_fixture(team, %{name: "Avery Chen"})
    activity = activity_fixture(team, %{started_at: ~U[2026-03-04 02:30:00Z]})
    attendance_fixture(activity, member, %{duration_in_minutes: 150})
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

    query = """
    select member, activity.started_at, hours
    from attendance
    format member as text, activity.started_at as date_time, hours as hours
    """

    lv |> form("#report-form", report: %{query: query}) |> render_change()

    assert has_element?(lv, "#report-preview td", "Avery Chen")
    refute has_element?(lv, "#report-preview td a", "Avery Chen")
    assert has_element?(lv, "#report-preview td", "Mar 3, 2026, 18:30")
    assert has_element?(lv, "#report-preview td", "2.5")
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

  test "the name and description come first, Save is at the top, and help can hide",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

    assert has_element?(lv, ".heading-row #report-save[form=report-form]")
    assert has_element?(lv, "label[for=report_about]", "Description")
    {name, _} = :binary.match(html, ~s(id="report_name"))
    {query, _} = :binary.match(html, ~s(id="report_query"))
    assert name < query

    # The toggle is the browser's (help_toggle.js): both links sit on the Query line, and
    # CSS shows one.
    assert has_element?(lv, "#report-editor[phx-hook=HelpToggle]")
    assert has_element?(lv, "#report-form .report-help-toggle #report-hide-help[data-help=hide]")
    assert has_element?(lv, "#report-form .report-help-toggle #report-show-help[data-help=show]")
    refute has_element?(lv, "#report-fields #report-hide-help")
    refute has_element?(lv, "#report-delete-button")
  end

  describe "an agent's live draft (#834)" do
    defp draft(query, attrs \\ %{}) do
      struct!(
        %Draft{query: query, agent: "Claude", at: ~U[2026-11-02 21:10:00Z]},
        attrs
      )
    end

    defp open_draft(conn, user, path, params) do
      conn |> log_in_user(user) |> live("#{path}?#{URI.encode_query(params)}")
    end

    test "the editor follows each query the agent checks", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      member_fixture(team, %{name: "Avery Chen"})

      params = %{query: "select title from groups", agent: "Claude", draft: "draft-one-id"}
      {:ok, lv, _html} = open_draft(conn, user, ~p"/teams/#{team}/reports/new", params)

      assert has_element?(lv, "#report-draft-following", "Following Claude's draft")
      assert has_element?(lv, "#report-preview-count", "the agent's query from")

      Draft.broadcast(
        team,
        user.id,
        "draft-one-id",
        draft("select name from members", %{name: "Everyone"})
      )

      assert has_element?(lv, "#report_name[value='Everyone']")
      assert has_element?(lv, "#report-preview", "Avery Chen")
      assert has_element?(lv, "#report-preview-count", "the agent's query from 14:10")

      lv |> form("#report-form") |> render_submit()
      report = App.Repo.get_by!(SavedReport, team_id: team.id, name: "Everyone")
      assert report.query == "select name from members"
      assert report.agent == "Claude"
    end

    test "another admin's, another draft's, and another report's updates don't reach it",
         %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      params = %{query: "select title from groups", agent: "Claude", draft: "draft-one-id"}
      {:ok, lv, _html} = open_draft(conn, user, ~p"/teams/#{team}/reports/new", params)

      Draft.broadcast(team, user.id + 1, "draft-one-id", draft("select name from members"))
      Draft.broadcast(team, user.id, "draft-two-id", draft("select name from members"))

      Draft.broadcast(
        team,
        user.id,
        "draft-one-id",
        draft("select name from members", %{report_id: 1})
      )

      assert has_element?(lv, "#report_query", "select title from groups")
    end

    test "after the admin types, a new query waits in a toast", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      params = %{query: "select title from groups", agent: "Claude", draft: "draft-one-id"}
      {:ok, lv, _html} = open_draft(conn, user, ~p"/teams/#{team}/reports/new", params)

      lv |> form("#report-form", report: %{query: "select name from members"}) |> render_change()
      assert has_element?(lv, "#report-preview-count", "runs as you type")

      Draft.broadcast(team, user.id, "draft-one-id", draft("select ref_id from members"))

      assert has_element?(lv, "#report_query", "select name from members")
      assert has_element?(lv, "#report-draft-toasts", "New query from Claude")

      lv |> element("#report-draft-load") |> render_click()
      assert has_element?(lv, "#report_query", "select ref_id from members")
      refute has_element?(lv, "#report-draft-toasts")
    end

    test "Stop following keeps the form as it is", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      params = %{query: "select title from groups", agent: "Claude", draft: "draft-one-id"}
      {:ok, lv, _html} = open_draft(conn, user, ~p"/teams/#{team}/reports/new", params)

      lv |> element("#report-draft-stop") |> render_click()
      refute has_element?(lv, "#report-draft-following")
      assert render(lv) =~ "Stopped following Claude&#39;s draft."

      Draft.broadcast(team, user.id, "draft-one-id", draft("select name from members"))
      assert has_element?(lv, "#report_query", "select title from groups")
    end

    test "names an agent that gave no name as an AI agent", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      params = %{query: "select title from groups", agent: "An AI agent", draft: "draft-one-id"}
      {:ok, lv, _html} = open_draft(conn, user, ~p"/teams/#{team}/reports/new", params)

      assert has_element?(lv, "#report-draft-following", "Following an AI agent's draft")
    end

    test "a saved report's draft lands on its edit page", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      {:ok, report} =
        SaveReport.call(team, user, nil, %{
          "name" => "Groups",
          "query" => "select title from groups"
        })

      params = %{query: "select title from groups", agent: "Claude", draft: "draft-one-id"}

      {:ok, lv, _html} =
        open_draft(conn, user, ~p"/teams/#{team}/reports/#{report.id}/edit", params)

      Draft.broadcast(
        team,
        user.id,
        "draft-one-id",
        draft("select name from members", %{report_id: report.id, change: "Members, not groups"})
      )

      assert has_element?(lv, "#report_query", "select name from members")
      assert has_element?(lv, "#report_name[value='Groups']")
      assert has_element?(lv, "#report_change[value='Members, not groups']")
    end
  end

  describe "History and Recently deleted (#834)" do
    test "History lists every save, and Restore saves a new version", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      {:ok, report} =
        SaveReport.call(
          team,
          user,
          nil,
          %{"name" => "Groups", "query" => "select title from groups"},
          DateTime.utc_now(),
          "Claude"
        )

      {:ok, report} =
        SaveReport.call(team, user, report, %{
          "query" => "select title from groups order by title",
          "change" => "Adds about"
        })

      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}")
      assert has_element?(lv, "#report-history")
      refute has_element?(lv, "#report-actions", "draft")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}/history")
      [latest, first] = ReportVersion.get_all(report)
      assert has_element?(lv, "#version-#{latest.id}", "Adds about")
      assert has_element?(lv, "#version-#{first.id}", "from Claude's draft")
      refute has_element?(lv, "#version-restore-#{latest.id}")

      {:ok, lv, _html} =
        lv |> element("#version-restore-#{first.id}") |> render_click() |> follow_redirect(conn)

      assert has_element?(lv, "#report_query", "select title from groups")
      lv |> form("#report-form", report: %{change: "Back to titles"}) |> render_submit()

      assert SavedReport.get(team, report.id).query == "select title from groups"
      assert [%{change: "Back to titles"}, _, _] = ReportVersion.get_all(report)
    end

    test "the byline names the agent whose draft the last save came from", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      {:ok, report} =
        SaveReport.call(
          team,
          user,
          nil,
          %{"name" => "Groups", "query" => "select title from groups"},
          DateTime.utc_now(),
          "Claude"
        )

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/#{report.id}")

      assert has_element?(lv, "#report-actions", "from Claude's draft.")
    end

    test "a deleted report waits under Recently deleted, and Restore brings it back",
         %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      conn = log_in_user(conn, user)

      {:ok, report} =
        SaveReport.call(team, user, nil, %{
          "name" => "Groups",
          "query" => "select title from groups"
        })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports")
      refute has_element?(lv, "#report-view-deleted")

      SaveReport.delete(report)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports")
      refute has_element?(lv, "#report-#{report.id}")
      assert has_element?(lv, "#report-view-deleted", "Recently deleted")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports?show=deleted")
      assert has_element?(lv, "#report-#{report.id}", "Groups")
      lv |> element("#report-restore-#{report.id}") |> render_click()

      assert SavedReport.get(team, report.id)
      refute has_element?(lv, "#report-view-deleted")
      assert render(lv) =~ "Restored the Groups report."
    end
  end

  test "contact details draw as a member's page does, and a place opens in maps (#827)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member_fixture(team, %{name: "Avery Chen", phone: "604-555-0101", email: "avery@example.com"})
    activity_fixture(team, %{title: "Night search", coordinate: "49.30000,-123.10000"})

    {:ok, report} =
      SaveReport.call(team, user, nil, %{
        "name" => "Contacts",
        "query" => "select name, mobile, email from members where name = 'Avery Chen'"
      })

    {:ok, places} =
      SaveReport.call(team, user, nil, %{
        "name" => "Places",
        "query" => "select title, place from activities where place is not null"
      })

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}")
    assert has_element?(lv, "#report-rows-0-1-call")
    assert has_element?(lv, "#report-rows-0", "avery@example.com")
    assert has_element?(lv, "#report-rows-0-2")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{places.id}")
    assert has_element?(lv, ~s(#report-rows-0-1[href*="google.com/maps"]), "49.30000, -123.10000")
  end

  test "Copy report starts from a built-in report", %{conn: conn} do
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
    assert has_element?(lv, "#report-actions", "Saved by")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}/edit")
    lv |> form("#report-form", report: %{name: "Group list"}) |> render_submit()
    assert_redirect(lv, ~p"/teams/#{team}/reports/#{report.id}")
    assert SavedReport.get(team, report.id).name == "Group list"

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}")
    lv |> element("#report-delete") |> render_click()
    assert_redirect(lv, ~p"/teams/#{team}/reports")
    assert SavedReport.get(team, report.id) == nil
  end

  test "a Kind column draws the kind's marker, and the Activity cell leaves its own out",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, %{title: "Overdue kayaker", activity_kind: "incident"})
    conn = log_in_user(conn, user)

    {:ok, with_kind} =
      SaveReport.call(team, user, nil, %{
        "name" => "With kind",
        "query" => "select title, kind from activities"
      })

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{with_kind.id}")
    assert has_element?(lv, "td[data-label=Kind] .marker-incident", "Incident")
    refute has_element?(lv, "td[data-label=Activity] .marker")

    {:ok, title_only} =
      SaveReport.call(team, user, nil, %{
        "name" => "Title",
        "query" => "select title from activities"
      })

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{title_only.id}")
    assert has_element?(lv, "td[data-label=Activity] .marker-incident")
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
