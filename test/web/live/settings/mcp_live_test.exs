defmodule Web.Settings.MCPLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
  alias App.Model.MCPToken
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

  test "doesn't exist, or show in team settings, while MCP is off", %{conn: conn, team: team} do
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/settings/mcp") end

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings")
    refute has_element?(lv, "#settings-mcp")
    assert has_element?(lv, "#settings-mcp-off", "ask a SAR Duty admin")
  end

  test "a manager creates a token, sees it once, and revokes it", ctx do
    %{conn: conn, admin: admin} = ctx
    team = turn_on(ctx.team, admin)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings")
    assert has_element?(lv, "#settings-mcp")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    assert has_element?(lv, "#no-tokens")

    lv
    |> form("#new-token-form", token: %{name: "Laptop", no_training: "true"})
    |> render_submit()

    [record] = MCPToken.get_live_for_team(team)

    token =
      lv
      |> element("#new-token-value")
      |> render()
      |> then(&Regex.run(~r/sarduty_mcp_[\w-]+/, &1))
      |> hd()

    assert MCPToken.hash(token) == record.token_hash
    assert has_element?(lv, "#claude-code-command", token)
    assert has_element?(lv, "#setup-prompt", token)
    assert has_element?(lv, "#token-#{record.id}", "Laptop")

    {:ok, lv, html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    refute html =~ token
    refute has_element?(lv, "#new-token")

    lv |> element("#revoke-token-#{record.id}") |> render_click()
    assert Repo.reload!(record).revoked_at
    refute has_element?(lv, "#token-#{record.id}")
  end

  test "a token needs a name", %{conn: conn, admin: admin} = ctx do
    team = turn_on(ctx.team, admin)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")

    html = lv |> form("#new-token-form", token: %{name: " "}) |> render_submit()
    assert html =~ "Enter a name for the token"
    assert MCPToken.get_live_for_team(team) == []
  end

  test "a token needs the promise not to train", %{conn: conn, admin: admin} = ctx do
    team = turn_on(ctx.team, admin)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    assert has_element?(lv, "#no-training")

    html =
      lv
      |> form("#new-token-form", token: %{name: "Laptop", no_training: "false"})
      |> render_submit()

    assert html =~ "then check this box"
    assert MCPToken.get_live_for_team(team) == []
  end

  test "an admin who doesn't manage the team cannot create one", %{admin: admin} = ctx do
    team = turn_on(ctx.team, admin)
    {:ok, lv, _html} = live(log_in_user(build_conn(), admin), ~p"/teams/#{team}/settings/mcp")

    assert has_element?(lv, "#cannot-create")
    refute has_element?(lv, "#new-token-form")
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
