defmodule Web.Admin.TeamLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.TeamLoginGrant
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{name: "Coast Range SAR"}})
    admin = make_admin(user)
    %{conn: log_in_user(conn, admin), admin: admin, team: team}
  end

  test "shows the team's facts, and its organization", %{conn: conn, team: team} do
    organization_fixture([team], %{name: "Western SAR Association", slug: "wsara"})
    {:ok, lv, _html} = live(conn, ~p"/admin/teams/#{team.id}")

    assert has_element?(lv, "#team-facts", team.subdomain)
    assert has_element?(lv, ~s|#team-organization a[href="/orgs/wsara/teams/#{team.subdomain}"]|)
    assert has_element?(lv, "#open-team")
  end

  test "lists team admins once per email, with D4H access and login grants",
       %{conn: conn, team: team} do
    manager_fixture(team, %{email: "Owner@example.com"})
    TeamLoginGrant.grant!(team.subdomain, "owner@example.com", "Treasurer")
    TeamLoginGrant.grant!(team.subdomain, "office@example.com", nil)

    {:ok, lv, _html} = live(conn, ~p"/admin/teams/#{team.id}")

    assert has_element?(lv, "#team-admin-owner\\@example\\.com", "D4H Owner")
    assert has_element?(lv, "#team-admin-owner\\@example\\.com", "Login grant: Treasurer")
    assert has_element?(lv, "#team-admin-office\\@example\\.com", "Never")
  end

  # Oban runs inline in tests, so the refresh runs; with no key it fails at once.
  test "Refresh refreshes the team", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/admin/teams/#{team.id}")

    lv |> element("#refresh-team") |> render_click()
    assert Repo.reload!(team).d4h_refresh_result =~ "Error"
  end

  test "turns ID cards and MCP on and off", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/admin/teams/#{team.id}")

    lv |> element("#id-cards-off") |> render_click()
    refute Repo.reload!(team).id_cards_enabled
    assert has_element?(lv, "#team-id-cards-state", "Off")

    lv |> element("#mcp-on") |> render_click()
    assert Repo.reload!(team).mcp_enabled
    assert has_element?(lv, "#team-mcp-state", "On")
  end

  test "is a 404 for team admins and organization admins", %{conn: conn, team: team} do
    %{user: team_admin} = user_with_team_fixture()
    org_admin = user_fixture()
    organization_admin_fixture(organization_fixture([team]), org_admin.email)

    for user <- [team_admin, org_admin] do
      assert_error_sent 404, fn ->
        conn |> log_in_user(user) |> get(~p"/admin/teams/#{team.id}")
      end
    end
  end

  test "an unknown id is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/admin/teams/999999") end
    assert_error_sent 404, fn -> get(conn, "/admin/teams/abc") end
  end
end
