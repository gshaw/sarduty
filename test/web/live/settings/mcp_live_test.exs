defmodule Web.Settings.MCPLiveTest do
  # Team settings' Agents tab (#761): the address to paste, and the agents connected.
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
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

  test "is not found, and has no tab, until a SAR Duty admin turns Agents on", ctx do
    assert_raise Web.Status.NotFound, fn ->
      live(ctx.conn, ~p"/teams/#{ctx.team}/settings/mcp")
    end

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/settings")
    refute has_element?(lv, ".tabs a", "Agents")
  end

  test "shows the address to paste, and disconnects an agent", ctx do
    %{conn: conn, user: user, admin: admin} = ctx
    team = turn_on(ctx.team, admin)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings")
    assert has_element?(lv, ~s{.tabs a[href="/teams/#{team.subdomain}/settings/mcp"]}, "Agents")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    assert has_element?(lv, "#no-agents")
    assert has_element?(lv, "#no-training")
    assert has_element?(lv, "#agent-address", "/teams/#{team.subdomain}/mcp")
    assert has_element?(lv, "#claude-code-command", "claude mcp add --transport http")
    refute has_element?(lv, "#token-create")

    %{connection: connection} = agent_connection_fixture(team, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    assert has_element?(lv, "#agent-#{connection.id}", "Laptop agent")
    assert has_element?(lv, "#agent-#{connection.id}", user.email)

    lv |> element("#disconnect-agent-#{connection.id}") |> render_click()
    assert Repo.reload!(connection).revoked_at
    refute has_element?(lv, "#agent-#{connection.id}")
  end

  test "lists no agent that never traded its code", %{admin: admin} = ctx do
    team = turn_on(ctx.team, admin)
    %{connection: connection} = agent_connection_fixture(team, ctx.user)
    connection |> Ecto.Changeset.change(connected_at: nil) |> Repo.update!()

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{team}/settings/mcp")
    assert has_element?(lv, "#no-agents")
  end

  test "never disconnects another team's agent", %{conn: conn, admin: admin} = ctx do
    team = turn_on(ctx.team, admin)
    %{user: other_user, team: other_team} = user_with_team_fixture()
    other_team = turn_on(other_team, admin)
    %{connection: theirs} = agent_connection_fixture(other_team, other_user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/mcp")
    render_click(lv, "disconnect", %{"id" => Integer.to_string(theirs.id)})

    refute Repo.reload!(theirs).revoked_at
  end
end
