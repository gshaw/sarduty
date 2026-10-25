defmodule Web.Admin.MCPLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MCPCall
  alias App.Operation.CreateMCPToken
  alias App.Repo

  test "the team's page turns MCP on; calls list here; off revokes its tokens", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    admin = make_admin(user)
    conn = log_in_user(conn, admin)

    {:ok, team_lv, _html} = live(conn, ~p"/admin/teams/#{team.id}")
    team_lv |> element("#mcp-on") |> render_click()
    assert Repo.reload!(team).mcp_enabled

    team = Repo.reload!(team)

    {:ok, _token, record} =
      CreateMCPToken.call(team, user, %{"name" => "Laptop", "no_training" => "true"})

    record = Repo.preload(record, :team)

    call =
      MCPCall.record!(
        token: record,
        tool: "list_activities",
        arguments: %{"from" => "2026-01-01"},
        row_count: 12
      )

    {:ok, lv, _html} = live(conn, ~p"/admin/mcp")
    assert has_element?(lv, "#mcp-call-#{call.id}", "list_activities")
    assert has_element?(lv, "#mcp-call-#{call.id}", "from: 2026-01-01")
    assert has_element?(lv, "#mcp-call-#{call.id}", "Laptop")
    refute has_element?(lv, "#mcp-teams")

    team_lv |> element("#mcp-off") |> render_click()
    refute Repo.reload!(team).mcp_enabled
    assert Repo.reload!(record).revoked_at
  end

  test "is for admins only", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    assert_raise Web.Status.NotFound, fn -> live(log_in_user(conn, user), ~p"/admin/mcp") end
  end
end
