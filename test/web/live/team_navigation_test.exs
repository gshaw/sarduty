defmodule Web.TeamNavigationTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), user: user, team: team}
  end

  test "a team page names the team, lists its pages down the left, and marks the current one",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members")

    assert has_element?(lv, ~s{#nav-area[href="/teams/#{team.subdomain}"]}, team.name)
    assert has_element?(lv, "#nav-area", "Team")
    assert has_element?(lv, ~s{#side-nav-activities[href="/teams/#{team.subdomain}/activities"]})
    assert has_element?(lv, "#side-nav-members[aria-current=page]")
    refute has_element?(lv, "#side-nav-activities[aria-current]")
    refute has_element?(lv, "#side-nav-dashboard[aria-current]")
    assert has_element?(lv, ~s{#side-nav-settings[href="/teams/#{team.subdomain}/settings"]})
  end

  test "the account menu switches areas", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

    assert has_element?(lv, "#side-nav-dashboard[aria-current=page]")
    assert has_element?(lv, "#nav-team-#{team.subdomain}[aria-current=page]", "Team area")
    assert has_element?(lv, ~s{#nav-your-settings[href="/account"]})
    assert has_element?(lv, ~s{#nav-log-out[href="/logout"]})
    refute has_element?(lv, "#nav-admin")
  end

  test "a team with proposed changes waiting counts them", %{conn: conn, team: team} do
    team = team |> Ecto.Changeset.change(mcp_enabled: true) |> Repo.update!()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities")
    refute has_element?(lv, "#side-nav-proposed-changes .badge")

    ChangeSet.propose!(%ChangeSet{team_id: team.id, source: :agent}, [])
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities")
    assert has_element?(lv, "#side-nav-proposed-changes .badge", "1")
  end

  test "site admins get Admin, and its pages down the left", %{conn: conn, user: user} do
    make_admin(user)
    {:ok, lv, _html} = live(conn, ~p"/admin/orgs")

    assert has_element?(lv, "#nav-area", "Admin")
    assert has_element?(lv, ~s{#nav-admin[href="/admin"][aria-current=page]})
    assert has_element?(lv, "#side-nav-admin-orgs[aria-current=page]")
    refute has_element?(lv, "#side-nav-admin-teams[aria-current]")
  end

  test "phones get the area's pages and the account menu behind a Menu button",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members")

    assert has_element?(lv, "#phone-menu #phone-menu-button", "Menu")
    assert has_element?(lv, "#phone-nav-area", team.name)

    assert has_element?(
             lv,
             ~s{#phone-menu #phone-nav-activities[href="/teams/#{team.subdomain}/activities"]}
           )

    assert has_element?(lv, "#phone-menu #phone-nav-members[aria-current=page]")
    assert has_element?(lv, "#phone-menu #phone-nav-team-#{team.subdomain}[aria-current=page]")
    assert has_element?(lv, ~s{#phone-menu #phone-nav-your-settings[href="/account"]})
    assert has_element?(lv, ~s{#phone-menu #phone-nav-log-out[href="/logout"]})
    refute has_element?(lv, "#phone-nav-admin")
  end

  test "a section's own page has no breadcrumbs; a record's starts at its section",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members")
    refute has_element?(lv, ".breadcrumbs")

    member = member_fixture(team, %{name: "Casey Dhillon"})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}")

    assert has_element?(
             lv,
             ~s{.breadcrumbs a[href="/teams/#{team.subdomain}/members/"]},
             "Members"
           )

    assert has_element?(lv, ".breadcrumbs [aria-current=page]", "Casey Dhillon")
    assert has_element?(lv, "#side-nav-members[aria-current=page]")
    refute has_element?(lv, ".breadcrumbs", team.name)
  end
end
