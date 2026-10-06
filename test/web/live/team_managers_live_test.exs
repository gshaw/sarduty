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

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/managers")

    assert has_element?(lv, "#manager-#{editor.id}", "Editor")
    refute has_element?(lv, "#team-managers", "Mo Member")
    assert has_element?(lv, "#grant-#{grant.id}", "office@example.com")
  end

  test "leaves out the SAR Duty account that holds the team key", %{conn: conn} do
    key = %{d4h_access_key_member_id: 900, d4h_access_key_owner: "SAR Duty"}
    %{user: user, team: team} = user_with_team_fixture(%{team: key})

    _sar_duty = manager_fixture(team, %{name: "SAR Duty", d4h_member_id: 900})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/managers")

    refute has_element?(lv, "#team-managers", "SAR Duty")
  end

  test "keeps a person whose own key is the team key", %{conn: conn} do
    key = %{d4h_access_key_member_id: 901, d4h_access_key_owner: "Kim Lee"}
    %{user: user, team: team} = user_with_team_fixture(%{team: key})

    kim = manager_fixture(team, %{name: "Kim Lee", d4h_member_id: 901})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/managers")

    assert has_element?(lv, "#manager-#{kim.id}", "Kim Lee")
  end
end
