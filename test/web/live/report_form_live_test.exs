defmodule Web.ReportFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ReportVersion
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

  test "the field list has the team's custom fields, and a report reads them (#840)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    task =
      custom_field_fixture(team, %{
        title: "Task type",
        field_type: "single_choice",
        options: [%{"id" => 1, "label" => "Search"}, %{"id" => 2, "label" => "Rescue"}]
      })

    activity_fixture(team, %{
      activity_kind: "incident",
      custom_values: %{"#{task.d4h_custom_field_id}" => [2]}
    })

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

    lv
    |> form("#report-form", report: %{query: "select title from activities"})
    |> render_change()

    assert has_element?(
             lv,
             "#report-fields button[data-field='`Task type`'][title*=\"One of 'Search' or 'Rescue'.\"]",
             "`Task type`"
           )

    assert has_element?(
             lv,
             "#report-field-meanings[href='/teams/#{team.subdomain}/settings/fields']"
           )

    lv
    |> form("#report-form",
      report: %{query: "select `Task type`, count(id) from activities group by `Task type`"}
    )
    |> render_change()

    assert has_element?(lv, "#report-preview", "Rescue")
  end

  # Agents connected through MCP linked here with their query (#816) until #1087.
  test "an old agent link's query and agent are ignored", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    params = %{query: "select title from groups", name: "Everyone", agent: "Claude"}
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new?#{params}")

    refute has_element?(lv, "#report_query", "select title from groups")
    lv |> form("#report-form", report: %{name: "Everyone"}) |> render_submit()

    report = App.Repo.get_by!(SavedReport, team_id: team.id, name: "Everyone")
    refute report.query =~ "groups"
    assert report.agent == nil
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

  test "the name is the title, and Rename shows its fields", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")
    assert has_element?(lv, "h1#report-title", "New report")

    lv
    |> form("#report-form", report: %{name: "Everyone", about: "All of us"})
    |> render_change()

    assert has_element?(lv, "h1#report-title", "Everyone")
    assert has_element?(lv, "#report-about.lead", "All of us")
    assert has_element?(lv, "#report-names-hidden[hidden] #report_name")

    lv |> form("#report-form", report: %{name: "Members"}) |> render_change()
    assert has_element?(lv, "h1#report-title", "Members")

    # Rename is a step: the fields, with the rest hidden until Rename or Cancel.
    lv |> element("#report-rename") |> render_click()
    assert has_element?(lv, "#report-names:not([hidden]) #report_name")
    refute has_element?(lv, "#report-rename")
    assert has_element?(lv, "#report-body.hidden")
    refute has_element?(lv, "#report-fields")

    lv |> form("#report-form", report: %{name: "Crew"}) |> render_change()
    lv |> element("#report-rename-cancel") |> render_click()
    assert has_element?(lv, "h1#report-title", "Members")
    refute has_element?(lv, "#report-body.hidden")
    assert has_element?(lv, "#report-fields")

    lv |> element("#report-rename") |> render_click()
    lv |> form("#report-form", report: %{name: "Crew"}) |> render_change()
    lv |> element("#report-rename-keep") |> render_click()
    assert has_element?(lv, "h1#report-title", "Crew")
    assert has_element?(lv, "#report-names-hidden[hidden] #report_name")
  end

  test "a new report is New report until named, and Save asks for a name", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

    assert has_element?(lv, "h1#report-title", "New report")
    refute has_element?(lv, "#report-query-toggle")

    lv |> form("#report-form") |> render_submit()
    assert has_element?(lv, "#report-names #report_name")
    assert has_element?(lv, "#report-form", "Enter a name for the report")
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

    # The fields show under the query.
    assert has_element?(lv, "#report-fields")
    refute has_element?(lv, "#report-delete-button")
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

  test "a chart report draws its chart above its rows, and the editor as you type (#826)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), -3, :day)})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/activities-by-month")
    assert has_element?(lv, "#report-chart-columns")
    assert has_element?(lv, "#report-rows")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/activities-this-year")
    assert has_element?(lv, "#report-chart-stat", "Activities")

    activity_fixture(team, %{
      coordinate: "49.30000,-123.10000",
      started_at: DateTime.add(DateTime.utc_now(), -2, :day)
    })

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/where-the-team-went")
    assert has_element?(lv, "#report-chart-map circle.is-recent")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/new")
    assert has_element?(lv, "#report-charts-link[href='/agents/reports#charts']")

    lv
    |> form("#report-form",
      report: %{
        query:
          "select date(started_at), count(id)\nfrom activities\nwhere started_at = LAST_N_DAYS:30\ngroup by date(started_at)\nchart calendar"
      }
    )
    |> render_change()

    assert has_element?(lv, "#report-preview-chart-calendar")
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

  describe "AI writing" do
    alias App.AccountsFixtures
    alias App.Model.AIAsk
    alias App.Operation.AskAI
    alias App.Operation.SetAISettings
    alias App.Report.BuiltIn

    setup do
      admin = make_admin(AccountsFixtures.user_fixture())
      params = %{access: "everyone", model: "claude-sonnet-5-5", monthly_budget: "50"}
      {:ok, _settings} = SetAISettings.call(params, admin)
      :ok
    end

    # Claude checks the query once, then answers with it. Each request goes to the test
    # as {:claude, request}. A History line's request, with no tools, gets `line`.
    defp stub_claude(query, note, more) do
      test = self()

      Req.Test.stub(App.Adapter.Claude, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)
        send(test, {:claude, request})
        Req.Test.json(conn, response(request, query, note, more))
      end)
    end

    defp response(%{"tools" => nil}, _query, _note, more),
      do: answer(%{"line" => more[:line] || "Added standing."})

    defp response(request, query, note, more) do
      case List.last(request["messages"]) do
        %{"content" => [%{"type" => "tool_result"} | _]} ->
          answer(
            Map.merge(%{"query" => query, "name" => "", "about" => "", "note" => note}, more)
          )

        _first ->
          %{
            "stop_reason" => "tool_use",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "call_1",
                "name" => "check_report",
                "input" => %{"query" => query}
              }
            ],
            "usage" => %{"input_tokens" => 9_000, "output_tokens" => 200}
          }
      end
    end

    defp answer(output) do
      %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => Jason.encode!(output)}],
        "usage" => %{"input_tokens" => 900, "output_tokens" => 300}
      }
    end

    test "a blank New report starts from the box and the built-in reports", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

      assert has_element?(lv, "#report-start #report-ai-form", "Describe the report you want")
      assert has_element?(lv, "#report-start #report-ai-form", "a chart of incidents by month")
      assert has_element?(lv, "#report-ai-ask", "Write it")
      assert has_element?(lv, "#report-body.hidden")
      refute has_element?(lv, "#report-ai")
      refute has_element?(lv, "#report-about")

      assert has_element?(
               lv,
               "#report-start-activities-by-month a[href='/teams/#{team.subdomain}/reports/new?from=activities-by-month']"
             )

      assert has_element?(lv, "#report-start-activities-by-month .icon-chart-column")
      assert has_element?(lv, "#report-start-qualification-coverage .icon-chart-bar")
      refute has_element?(lv, "#report-start-hours-by-member .report-start-chart")
      count = length(BuiltIn.for_team(team))
      assert has_element?(lv, "#report-start-all", "All #{count} built-in reports")

      lv |> element("#report-write-own") |> render_click()
      refute has_element?(lv, "#report-start")
      refute has_element?(lv, "#report-body.hidden")
      refute has_element?(lv, ".hidden #report_query")
      assert has_element?(lv, "#report-ai #report-ai-form", "Ask AI")
      assert has_element?(lv, "textarea[name='ai[ask]'][phx-hook=AskEnter]")
      assert has_element?(lv, "#report-ai-form .ai-enter-hint", "Enter sends it.")
    end

    # Try next (#1089): the asks AI suggests after its reply. A tap puts one in the box;
    # nothing is sent. Adminland can turn them off for reports.
    test "Try next shows AI's suggested asks, and a tap puts one in the box", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      stub_claude("select name from members order by name", "Lists every member.", %{
        "next" => ["Add each member's standing", "  ", "Only counted members"]
      })

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")
      lv |> form("#report-ai-form", ai: %{ask: "every member"}) |> render_submit()
      render_async(lv)

      assert_received {:claude, request}
      assert "next" in request["output_config"]["format"]["schema"]["required"]
      assert has_element?(lv, "#report-ai-next", "Try next")
      assert has_element?(lv, "#report-ai-next-1", "Only counted members")
      refute has_element?(lv, "#report-ai-next-2")

      lv |> element("#report-ai-next-0") |> render_click()
      assert has_element?(lv, "textarea[name='ai[ask]']", "Add each member's standing")
    end

    test "with suggestions off for reports, AI is never asked for them", %{conn: conn} do
      {:ok, _settings} =
        SetAISettings.call(
          %{
            access: "everyone",
            model: "claude-sonnet-5-5",
            monthly_budget: "50",
            suggest_reports: "false"
          },
          make_admin(AccountsFixtures.user_fixture())
        )

      %{user: user, team: team} = user_with_team_fixture()
      stub_claude("select name from members", "Lists every member.", %{})
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")
      lv |> form("#report-ai-form", ai: %{ask: "every member"}) |> render_submit()
      render_async(lv)

      assert_received {:claude, request}
      refute Map.has_key?(request["output_config"]["format"]["schema"]["properties"], "next")
      refute has_element?(lv, "#report-ai-next")
    end

    test "an ask writes the query, name, and description, the next carries it, and Undo puts it back",
         %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      stub_claude(
        "select name, last_attended from members order by name",
        "Shows when each member last came.",
        %{"name" => "Last came", "about" => "When each member last came."}
      )

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

      lv
      |> form("#report-ai-form", ai: %{ask: "when did each member last come"})
      |> render_submit()

      render_async(lv)

      assert has_element?(lv, "#report_query", "select name, last_attended from members")
      assert has_element?(lv, "h1#report-title", "Last came")
      assert has_element?(lv, "#report-about", "When each member last came.")
      assert has_element?(lv, "#report-ai .ai-you", "when did each member last come")
      assert has_element?(lv, "#report-ai .ai-reply", "Shows when each member last came.")
      assert has_element?(lv, "#report-ai #report-ai-form", "Ask AI")
      refute has_element?(lv, "#report-start")

      ask = App.Repo.get_by!(AIAsk, team_id: team.id)
      assert ask.outcome == :used
      assert ask.turns == 2
      assert ask.input_tokens == 9_900
      assert ask.cost_microdollars > 0

      lv |> form("#report-ai-form", ai: %{ask: "and their standing"}) |> render_submit()
      render_async(lv)
      assert_received {:claude, %{"messages" => [%{"content" => "Earlier asks" <> prompt} | _]}}
      assert prompt =~ "when did each member last come"
      assert prompt =~ "Shows when each member last came."

      # The second ask changed nothing, so the first has the only Undo.
      [_, id] = Regex.run(~r/id="report-ai-undo-(\d+)"/, render(lv))
      lv |> element("#report-ai-undo-#{id}") |> render_click()
      assert has_element?(lv, "#report_query", "where counted = true")
      assert has_element?(lv, "h1#report-title", "New report")
      refute has_element?(lv, "#report-ai-asks")
    end

    test "Stop puts the words back, and the ask counts with what it spent", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      test = self()

      # The first request answers; the second waits until the ask is stopped.
      Req.Test.stub(App.Adapter.Claude, fn conn ->
        if Process.get(:asked) do
          send(test, :waiting)
          Process.sleep(:infinity)
        end

        Process.put(:asked, true)

        Req.Test.json(conn, %{
          "stop_reason" => "tool_use",
          "content" => [
            %{"type" => "tool_use", "id" => "c1", "name" => "check_report", "input" => %{}}
          ],
          "usage" => %{"input_tokens" => 9_000, "output_tokens" => 200}
        })
      end)

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new?from=hours-by-member")

      box = box_id(lv)
      lv |> form("#report-ai-form", ai: %{ask: "add a menu for the period"}) |> render_submit()
      assert_receive :waiting

      # The ask shows at once, with its step and Stop, and the box waits.
      assert has_element?(lv, "#report-ai-ask-running", "add a menu for the period")
      assert has_element?(lv, "#report-ai-step", "Thinking…")
      assert has_element?(lv, "#report-ai-step #report-ai-stop")
      assert has_element?(lv, "#report-ai-ask[disabled]")
      refute has_element?(lv, "textarea[name='ai[ask]']", "add a menu for the period")
      # A new box, so one Safari leaves focused still clears.
      refute box_id(lv) == box

      lv |> element("#report-ai-stop") |> render_click()

      assert has_element?(lv, "textarea[name='ai[ask]']", "add a menu for the period")
      refute has_element?(lv, "#report-ai-asks")

      ask = App.Repo.get_by!(AIAsk, team_id: team.id)
      assert ask.outcome == :stopped
      assert ask.input_tokens == 9_000
      assert ask.cost_microdollars > 0
      assert AIAsk.count_today(team, DateTime.utc_now()) == 1
    end

    test "with AI writing on, What changed goes and AI writes the History line after the save",
         %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      {:ok, report} =
        SaveReport.call(team, user, nil, %{
          "name" => "Members",
          "query" => "select name from members"
        })

      stub_claude("", "", %{line: "Added each member's standing."})
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}/edit")
      refute has_element?(lv, "#report_change")

      lv
      |> form("#report-form", report: %{query: "select name, standing from members"})
      |> render_submit()

      assert_received {:claude, request}
      assert request["output_config"]["effort"] == "low"
      assert hd(request["messages"])["content"] =~ "select name, standing from members"

      assert [%{change: "Added each member's standing."}, %{change: nil}] =
               ReportVersion.get_all(report)

      line = App.Repo.get_by!(AIAsk, team_id: team.id)
      assert line.kind == :history_line
      assert line.ask == "Members"
      assert AIAsk.count_today(team, DateTime.utc_now()) == 0
    end

    test "a team that used today's asks is told so", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      for _n <- 1..AskAI.asks_per_day() do
        AIAsk.record!(
          team_id: team.id,
          kind: :report,
          model: "claude-sonnet-5-5",
          outcome: :used,
          asked_at: DateTime.utc_now()
        )
      end

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")
      refute has_element?(lv, "#report-ai-form")
      assert has_element?(lv, "#report-ai-closed", "used today's 100 asks")
    end

    test "with AI writing off there is no column, and What changed stays", %{conn: conn} do
      admin = make_admin(AccountsFixtures.user_fixture())
      params = %{access: "off", model: "claude-sonnet-5-5", monthly_budget: "50"}
      {:ok, _settings} = SetAISettings.call(params, admin)
      %{user: user, team: team} = user_with_team_fixture()
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/new")
      refute has_element?(lv, "#report-ai")
      refute has_element?(lv, "#report-start")
      assert has_element?(lv, "#report-fields")

      {:ok, report} =
        SaveReport.call(team, user, nil, %{
          "name" => "Members",
          "query" => "select name from members"
        })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}/edit")
      assert has_element?(lv, "#report_change")
    end
  end

  defp box_id(lv) do
    html = lv |> element("textarea[name='ai[ask]']") |> render()
    [id] = Regex.run(~r/ id="([^"]+)"/, html, capture: :all_but_first)
    id
  end

  # Not saved yet shows beside Save once the page differs from what's saved, and leaving
  # then asks first (assets/js/unsaved.js); Cancel never asks.
  test "Not saved yet shows once the report differs from what's saved", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)

    {:ok, report} =
      SaveReport.call(team, user, nil, %{
        "name" => "Members",
        "query" => "select name from members"
      })

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/#{report.id}/edit")
    assert has_element?(lv, "#report-unsaved[hidden][phx-hook=Unsaved]")
    assert has_element?(lv, "#report-cancel[data-leave-ok]")

    lv |> form("#report-form", report: %{name: "Members by name"}) |> render_change()
    assert has_element?(lv, "#report-unsaved[data-unsaved=true]:not([hidden])", "Not saved yet")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/reports/new?from=hours-by-member")
    assert has_element?(lv, "#report-unsaved:not([hidden])")
  end
end
