defmodule Web.TeamManagersLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.TeamLoginGrant

  test "lists the team's managers and admin grants, not other members", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    editor = manager_fixture(team, %{name: "Eli Editor", d4h_permission: 1})
    _member = manager_fixture(team, %{name: "Mo Member", d4h_permission: 2})
    grant = TeamLoginGrant.grant!(team.subdomain, "office@example.com", "role address")

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/#{team.subdomain}/managers")

    assert has_element?(lv, "#manager-#{editor.id}", "Editor")
    refute has_element?(lv, "#team-managers", "Mo Member")
    assert has_element?(lv, "#grant-#{grant.id}", "office@example.com")
  end
end
