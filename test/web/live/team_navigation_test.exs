defmodule Web.TeamNavigationTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), user: user, team: team}
  end

  test "team pages link to the team's sections and mark the current one", %{
    conn: conn,
    team: team
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members")

    assert has_element?(lv, ~s{#nav-activities[href="/#{team.subdomain}/activities"]})
    assert has_element?(lv, "#nav-members[aria-current=page]")
    refute has_element?(lv, "#nav-activities[aria-current]")
    refute has_element?(lv, "#nav-admin")
  end

  test "site admins get an Admin link", %{conn: conn, user: user, team: team} do
    make_admin(user)
    {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}")

    assert has_element?(lv, ~s{#nav-admin[href="/admin"]})
    assert has_element?(lv, "#nav-dashboard[aria-current=page]")
  end
end
