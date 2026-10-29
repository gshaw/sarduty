defmodule Web.Settings.MCPTokenFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
  alias App.Model.MCPToken
  alias App.Operation.SetTeamMCP

  setup %{conn: conn} do
    admin = make_admin(AccountsFixtures.user_fixture())
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, team} = SetTeamMCP.call(team, true, admin)
    %{conn: log_in_user(conn, user), team: team, admin: admin}
  end

  test "creates a token, then shows it once in place of the form", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp/new")

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
    refute has_element?(lv, "#new-token-form")
    assert has_element?(lv, "#claude-code-command", token)
    assert has_element?(lv, "#setup-prompt", token)
    assert has_element?(lv, ~s|#new-token-value-copy[value="#{token}"]|)
    assert has_element?(lv, "#setup-prompt-copy[aria-label='Copy setup prompt']")
    assert has_element?(lv, ~s|#token-done[href="/teams/#{team.subdomain}/settings/mcp"]|)

    {:ok, lv, html} = live(conn, ~p"/teams/#{team}/settings/mcp/new")
    refute html =~ token
    refute has_element?(lv, "#new-token")
    assert has_element?(lv, "#new-token-form")
  end

  test "a token needs a name", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp/new")

    html = lv |> form("#new-token-form", token: %{name: " "}) |> render_submit()
    assert html =~ "Enter a name for the token"
    assert MCPToken.get_live_for_team(team) == []
  end

  test "a token needs the promise not to train", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp/new")

    html =
      lv
      |> form("#new-token-form", token: %{name: "Laptop", no_training: "false"})
      |> render_submit()

    assert html =~ "then check this box"
    assert MCPToken.get_live_for_team(team) == []
  end

  test "is not found for an admin who doesn't manage the team", %{admin: admin, team: team} do
    assert_raise Web.Status.NotFound, fn ->
      live(log_in_user(build_conn(), admin), ~p"/teams/#{team}/settings/mcp/new")
    end
  end
end
