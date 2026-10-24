defmodule Web.MemberGroupsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "a team admin's groups link to each group", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    group = group_fixture(team, %{title: "Callout"})
    group_member_fixture(group, member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/groups")

    assert has_element?(
             lv,
             ~s{#member_groups a[href="/teams/#{team.subdomain}/groups/#{group.id}"]}
           )
  end

  # Group pages stay with team admins (#440).
  test "a member sees the groups as plain text", %{conn: conn} do
    %{team: team, user: user} = member_with_login_fixture()
    other = member_fixture(team)
    group_member_fixture(group_fixture(team, %{title: "Callout"}), other)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{other.id}/groups")

    assert has_element?(lv, "#member_groups td", "Callout")
    refute has_element?(lv, "#member_groups a")
  end
end
