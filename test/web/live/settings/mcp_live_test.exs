defmodule Web.Settings.MCPLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
  alias App.Operation.CallMCPTool
  alias App.Operation.CreateMCPToken
  alias App.Operation.SetTeamMCP
  alias App.Repo

  setup %{conn: conn} do
    admin = make_admin(AccountsFixtures.user_fixture())
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), user: user, team: team, admin: admin}
  end

  defp turn_on(team, admin) do
    {:ok, team} = SetTeamMCP.call(team, true, admin)
    team
  end

  test "is not found, and has no tab, until a SAR Duty admin turns MCP on", ctx do
    assert_raise Web.Status.NotFound, fn ->
      live(ctx.conn, ~p"/teams/#{ctx.team}/settings/mcp")
    end

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/settings")
    refute has_element?(lv, ".tabs a", "MCP tokens")
  end

  test "a manager opens Create token and revokes a token", ctx do
    %{conn: conn, user: user, admin: admin} = ctx
    team = turn_on(ctx.team, admin)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings")

    assert has_element?(
             lv,
             ~s{.tabs a[href="/teams/#{team.subdomain}/settings/mcp"]}
           )

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    assert has_element?(lv, "#no-tokens")
    assert has_element?(lv, "#agents-intro", "help you write reports")
    assert has_element?(lv, ~s(#agents-how[href="/agents"]))
    assert has_element?(lv, "#no-agent-reports")
    refute has_element?(lv, "#new-token-form")

    assert {:error, {:live_redirect, %{to: to}}} =
             lv |> element("#token-create") |> render_click()

    assert to == "/teams/#{team.subdomain}/settings/mcp/new"

    {:ok, _token, record} =
      CreateMCPToken.call(team, user, %{"name" => "Laptop"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    assert has_element?(lv, "#token-#{record.id}", "Laptop")
    assert has_element?(lv, "#connect-details", "/teams/#{team.subdomain}/mcp")
    refute has_element?(lv, "#claude-code-command")

    lv |> element("#revoke-token-#{record.id}") |> render_click()
    assert Repo.reload!(record).revoked_at
    refute has_element?(lv, "#token-#{record.id}")
  end

  test "lists the reports agents checked, and the ones that needed a fix (#816)", ctx do
    %{conn: conn, team: team, user: user, admin: admin} = ctx
    team = turn_on(team, admin)

    {:ok, _token, record} =
      CreateMCPToken.call(team, user, %{"name" => "Claude"})

    record = Repo.preload(record, :team)

    CallMCPTool.call(record, "check_report", %{
      "query" => "select name from members"
    })

    CallMCPTool.call(record, "check_report", %{"query" => "select nme from members"})

    saved =
      Repo.insert!(%App.Model.SavedReport{
        team_id: team.id,
        name: "Members",
        query: "select name from members"
      })

    CallMCPTool.call(record, "check_report", %{
      "query" => "select name, joined_at from members",
      "report_id" => saved.id
    })

    CallMCPTool.call(record, "try_report", %{"query" => "select title from activities"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")

    assert has_element?(lv, "#agent-reports td", "Claude")
    assert has_element?(lv, "#agent-reports td", "Needed a fix: Line 1: members has no field nme")
    refute has_element?(lv, "#agent-reports td", "select title from activities")

    assert has_element?(
             lv,
             ~s(#agent-reports a[href$="/teams/#{team.subdomain}/reports/new?agent=Claude&query=select+name+from+members"])
           )

    assert has_element?(
             lv,
             ~s(#agent-reports a[href*="/teams/#{team.subdomain}/reports/#{saved.id}/edit?agent=Claude"])
           )
  end

  test "an admin who doesn't manage the team cannot create one", %{admin: admin} = ctx do
    team = turn_on(ctx.team, admin)
    {:ok, lv, _html} = live(log_in_user(build_conn(), admin), ~p"/teams/#{team}/settings/mcp")

    assert has_element?(lv, "#cannot-create")
    refute has_element?(lv, "#token-create")
  end

  test "never revokes another team's token", %{conn: conn, admin: admin} = ctx do
    team = turn_on(ctx.team, admin)
    %{user: other_user, team: other_team} = user_with_team_fixture()
    other_team = turn_on(other_team, admin)

    {:ok, _token, theirs} =
      CreateMCPToken.call(other_team, other_user, %{"name" => "Theirs"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    render_click(lv, "revoke", %{"id" => Integer.to_string(theirs.id)})

    refute Repo.reload!(theirs).revoked_at
  end
end
