defmodule Web.Settings.MCPLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
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
    assert has_element?(lv, "#no-training")
    refute has_element?(lv, "#new-token-form")

    assert {:error, {:live_redirect, %{to: to}}} =
             lv |> element("#token-create") |> render_click()

    assert to == "/teams/#{team.subdomain}/settings/mcp/new"

    {:ok, _token, record} =
      CreateMCPToken.call(team, user, %{"name" => "Laptop", "no_training" => "true"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    assert has_element?(lv, "#token-#{record.id}", "Laptop")
    assert has_element?(lv, "#connect-details", "/teams/#{team.subdomain}/mcp")
    refute has_element?(lv, "#claude-code-command")

    lv |> element("#revoke-token-#{record.id}") |> render_click()
    assert Repo.reload!(record).revoked_at
    refute has_element?(lv, "#token-#{record.id}")
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
      CreateMCPToken.call(other_team, other_user, %{"name" => "Theirs", "no_training" => "true"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    render_click(lv, "revoke", %{"id" => Integer.to_string(theirs.id)})

    refute Repo.reload!(theirs).revoked_at
  end
end
