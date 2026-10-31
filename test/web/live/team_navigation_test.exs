defmodule Web.TeamNavigationTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), user: user, team: team}
  end

  test "a team page names the team, lists its pages down the left, and marks the current one",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members")

    assert has_element?(lv, "#team-switcher #nav-area", team.name)
    assert has_element?(lv, ~s{#side-nav-activities[href="/teams/#{team.subdomain}/activities"]})
    assert has_element?(lv, "#side-nav-members[aria-current=page]")
    refute has_element?(lv, "#side-nav-activities[aria-current]")
    refute has_element?(lv, "#side-nav-dashboard[aria-current]")
    assert has_element?(lv, ~s{#side-nav-settings[href="/teams/#{team.subdomain}/settings"]})
    refute has_element?(lv, "#side-nav-me")
    assert has_element?(lv, "#side-nav .side-nav-group", "Team settings")
  end

  test "the logo goes to the home page, whose bar names your team and switches back",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members")

    assert has_element?(lv, ~s{a.brand[href="/"]})
    assert has_element?(lv, "#team-switcher #nav-area", team.name)
    refute has_element?(lv, "#site-footer")

    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, ~s{a.brand[href="/"]})
    assert has_element?(lv, "#team-switcher summary", team.name)
    assert has_element?(lv, ~s{#switch-team-#{team.subdomain}[href="/teams/#{team.subdomain}"]})
    refute has_element?(lv, "#switch-team-#{team.subdomain}[aria-current]")
    assert has_element?(lv, "#site-footer")
  end

  test "a team admin who is a member gets Your membership last", %{conn: conn, team: team} do
    team |> Ecto.Changeset.change(member_logins: true) |> Repo.update!()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

    assert has_element?(
             lv,
             ~s{#side-nav .side-nav-group:last-child #side-nav-me[href="/teams/#{team.subdomain}/me"]},
             "Your membership"
           )
  end

  test "the account menu is the person, Account settings, and Log out",
       %{conn: conn, user: user, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

    assert has_element?(lv, "#account-menu .avatar")
    assert has_element?(lv, "#account-menu .menu-note", user.email)
    assert has_element?(lv, ~s{#account-menu #nav-account-settings[href="/account"]})
    assert has_element?(lv, ~s{#account-menu #nav-log-out[href="/logout"]})
    refute has_element?(lv, "#account-menu", team.name)
  end

  test "the team switcher lists the other places to go", %{conn: conn, user: user, team: team} do
    other = team_fixture(%{name: "Zulu SAR"})
    manager_fixture(other, %{email: user.email})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

    assert has_element?(lv, "#team-switcher #nav-area", team.name)
    assert has_element?(lv, "#switch-team-#{team.subdomain}[aria-current=page]")
    assert has_element?(lv, ~s{#switch-team-#{other.subdomain}[href="/teams/#{other.subdomain}"]})
    refute has_element?(lv, "#switch-admin")
    refute has_element?(lv, "#switch-styles")
  end

  test "Templates is in the menu, with no dot on the phone menu when nothing waits",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities")
    assert has_element?(lv, ~s{#side-nav-templates[href="/teams/#{team.subdomain}/templates"]})
    refute has_element?(lv, ".tabs")
  end

  test "Team settings' pages are tabs under one title", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/hours-tags")

    assert has_element?(lv, "h1", "Team settings")
    assert has_element?(lv, ".tabs a[aria-current=page]", "Hours tags")
    assert has_element?(lv, "#side-nav-settings[aria-current=page]")
    # MCP tokens shows only while MCP is on, which a team admin turns on in Features.
    assert has_element?(lv, ".tabs a", "Features")
    refute has_element?(lv, ".tabs a", "MCP tokens")
  end

  test "SAR Duty admins get SAR Duty admin, and its pages down the left",
       %{conn: conn, user: user, team: team} do
    make_admin(user)
    {:ok, lv, _html} = live(conn, ~p"/admin/orgs")

    assert has_element?(lv, "#nav-area", "SAR Duty admin")
    assert has_element?(lv, ~s{#switch-admin[href="/admin"][aria-current=page]})
    assert has_element?(lv, ~s{#switch-styles[href="/styles"]})
    assert has_element?(lv, "#switch-team-#{team.subdomain}")
    assert has_element?(lv, "#side-nav-admin-orgs[aria-current=page]")
    refute has_element?(lv, "#side-nav-admin-teams[aria-current]")
  end

  test "phones get the area's pages behind a Menu button, the switcher on the name, and the avatar",
       %{conn: conn, user: user, team: team} do
    team |> Ecto.Changeset.change(member_logins: true) |> Repo.update!()
    make_admin(user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members")

    assert has_element?(lv, "#phone-menu #phone-menu-button", "Menu")
    assert has_element?(lv, "#phone-nav-area", team.name)

    assert has_element?(
             lv,
             ~s{#phone-menu #phone-nav-activities[href="/teams/#{team.subdomain}/activities"]}
           )

    assert has_element?(lv, "#phone-menu #phone-nav-members[aria-current=page]")
    assert has_element?(lv, "#phone-menu #phone-nav-me", "Your membership")
    refute has_element?(lv, "#phone-menu #phone-switch-admin")
    assert has_element?(lv, "#phone-team-switcher summary", team.name)
    assert has_element?(lv, "#phone-team-switcher #phone-switch-admin.switch-admin")

    assert has_element?(
             lv,
             "#phone-team-switcher #phone-switch-team-#{team.subdomain}[aria-current=page]"
           )

    refute has_element?(lv, "#phone-nav-area > a.brand")
    refute has_element?(lv, "#phone-menu .menu-person")
    refute has_element?(lv, "#phone-menu a[href='/logout']")
    assert has_element?(lv, "#account-menu .menu-note", user.email)
    assert has_element?(lv, ~s{#account-menu #nav-log-out[href="/logout"]})
  end

  test "a member on one team gets the picker: Your team, then SAR Duty's home page (#779)" do
    team =
      %{name: "Alpha SAR"}
      |> team_fixture()
      |> Ecto.Changeset.change(member_logins: true)
      |> Repo.update!()

    user = App.AccountsFixtures.user_fixture()
    member_fixture(team, %{email: user.email})
    {:ok, lv, _html} = live(log_in_user(build_conn(), user), ~p"/teams/#{team}/me")

    assert has_element?(lv, ".site-bar-slash")
    assert has_element?(lv, "#team-switcher #nav-area", "Alpha SAR")
    assert has_element?(lv, "#team-switcher .menu-heading", "Your team")
    assert has_element?(lv, "#switch-team-#{team.subdomain}[aria-current=page]")
    assert has_element?(lv, ~s{#team-switcher #switch-home[href="/"]}, "Home page")
    assert has_element?(lv, "#phone-team-switcher summary", "Alpha SAR")
    assert has_element?(lv, "#phone-team-switcher .menu-heading", "Your team")
    assert has_element?(lv, ~s{#phone-team-switcher #phone-switch-home[href="/"]})
    refute has_element?(lv, "#switch-admin")
  end

  test "a member on two teams gets the switcher at every width, and no SAR Duty admin" do
    [first, second] =
      for name <- ["Alpha SAR", "Bravo SAR"] do
        %{name: name}
        |> team_fixture()
        |> Ecto.Changeset.change(member_logins: true)
        |> Repo.update!()
      end

    user = App.AccountsFixtures.user_fixture()
    member_fixture(first, %{email: user.email})
    member_fixture(second, %{email: user.email})
    {:ok, lv, _html} = live(log_in_user(build_conn(), user), ~p"/teams/#{first}/me")

    assert has_element?(lv, "#team-switcher #nav-area", "Alpha SAR")
    assert has_element?(lv, "#switch-team-#{first.subdomain}[aria-current=page]")

    assert has_element?(
             lv,
             ~s{#switch-team-#{second.subdomain}[href="/teams/#{second.subdomain}"]}
           )

    assert has_element?(lv, "#phone-team-switcher #phone-switch-team-#{second.subdomain}")
    assert has_element?(lv, "#team-switcher .menu-heading", "Your teams")
    refute has_element?(lv, "#switch-admin")
  end

  test "with no pages and nowhere to switch to, there is no Menu button, only the avatar" do
    user = App.AccountsFixtures.user_fixture()
    {:ok, lv, _html} = live(log_in_user(build_conn(), user), ~p"/account")

    assert has_element?(lv, "#account-menu .menu-note", user.email)
    refute has_element?(lv, "#phone-menu")
  end

  test "a section's own page has no breadcrumbs; a record's starts at its section",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members")
    refute has_element?(lv, ".breadcrumbs")

    member = member_fixture(team, %{name: "Casey Dhillon"})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}")

    assert has_element?(
             lv,
             ~s{.breadcrumbs a[href="/teams/#{team.subdomain}/members"]},
             "Members"
           )

    assert has_element?(lv, ".breadcrumbs [aria-current=page]", "Casey Dhillon")
    assert has_element?(lv, "#side-nav-members[aria-current=page]")
    refute has_element?(lv, ".breadcrumbs", team.name)
  end
end
