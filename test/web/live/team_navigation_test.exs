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
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members")

    assert has_element?(lv, ~s{#nav-activities[href="/teams/#{team.subdomain}/activities"]})
    assert has_element?(lv, "#nav-members[aria-current=page]")
    refute has_element?(lv, "#nav-activities[aria-current]")
    refute has_element?(lv, "#nav-admin")
  end

  test "site admins get an Admin link", %{conn: conn, user: user, team: team} do
    make_admin(user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

    assert has_element?(lv, ~s{#nav-admin[href="/admin"]})
    assert has_element?(lv, "#nav-dashboard[aria-current=page]")
  end

  test "phones get the same links behind a menu button", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members")

    assert has_element?(lv, "#phone-menu #phone-menu-button", "Menu")

    assert has_element?(
             lv,
             ~s{#phone-menu #phone-nav-activities[href="/teams/#{team.subdomain}/activities"]}
           )

    assert has_element?(lv, "#phone-menu #phone-nav-members[aria-current=page]")

    assert has_element?(
             lv,
             ~s{#phone-menu #phone-nav-team-settings[href="/teams/#{team.subdomain}/settings"]}
           )

    assert has_element?(lv, ~s{#phone-menu #phone-nav-account[href="/account"]})
    assert has_element?(lv, ~s{#phone-menu #phone-nav-log-out[href="/logout"]})
    refute has_element?(lv, "#phone-nav-admin")
  end

  test "site admins get Admin in the phone menu", %{conn: conn, user: user} do
    make_admin(user)
    {:ok, lv, _html} = live(conn, ~p"/admin")

    assert has_element?(lv, "#phone-menu #phone-nav-admin[aria-current=page]")
  end
end
