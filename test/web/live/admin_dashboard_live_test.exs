defmodule Web.AdminDashboardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team
  alias App.Model.TeamLoginGrant

  test "renders admin dashboard for admin users", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    user = make_admin(user)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin")

    assert html =~ "Admin"
  end

  test "shows each team's logo from the shared logo route", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    user = make_admin(user)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/admin")

    assert has_element?(
             lv,
             ~s(#team-#{team.id}-logo[src="/teams/#{team.subdomain}/logo?shape=square"])
           )
  end

  test "lists each team's users", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)

    %{user: first, team: team} = user_with_team_fixture()
    second = App.AccountsFixtures.user_fixture()
    manager_fixture(team, %{email: second.email, d4h_permission: 1})

    {:ok, lv, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    row = "#team-#{team.id}"

    assert has_element?(lv, "#{row} li", first.email)
    assert has_element?(lv, "#{row} li", second.email)
    refute has_element?(lv, "#{row} a[href^='mailto:']")
  end

  test "says whose D4H account each team key is", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)

    sar_duty = team_fixture(%{d4h_access_key: "k1", d4h_access_key_owner: "SAR Duty"})
    person = team_fixture(%{d4h_access_key: "k2", d4h_access_key_owner: "Sam Rivers"})
    no_key = team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert has_element?(lv, "#team-#{sar_duty.id}-key", "Team key: SAR Duty")
    assert has_element?(lv, "#team-#{person.id}-key", "Person's key: Sam Rivers")
    assert has_element?(lv, "#team-#{no_key.id}-key", "No team key")
  end

  test "lists each team's managers", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)

    team = team_fixture(%{d4h_access_key_member_id: 900, d4h_access_key_owner: "SAR Duty"})
    kept = App.AccountsFixtures.user_fixture()
    manager = &manager_fixture(team, &1)

    owner = manager.(%{name: "Ada Owner", email: kept.email})
    editor = manager.(%{name: "Eli Editor", email: "eli@other.org", d4h_permission: 1})
    _sar_duty = manager.(%{name: "SAR Duty", d4h_member_id: 900})
    _member = manager.(%{name: "Mo Member", d4h_permission: 2})
    _retired = manager.(%{name: "Rae Retired", d4h_status: "RETIRED"})

    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert has_element?(lv, "#managers-#{team.id} h3", "2 managers")
    assert has_element?(lv, "#manager-#{owner.id}", "Has login")
    assert has_element?(lv, "#manager-#{editor.id}", "Editor")
    refute has_element?(lv, "#managers-#{team.id}", "SAR Duty")
    refute has_element?(lv, "#managers-#{team.id}", "Mo Member")
    refute has_element?(lv, "#managers-#{team.id}", "Rae Retired")
  end

  test "lists emails an admin let in, and counts their logins", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)
    team = team_fixture()
    grant = TeamLoginGrant.grant!(team.subdomain, "office@example.com", "role address")
    App.AccountsFixtures.user_fixture(%{email: "office@example.com"})

    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert has_element?(lv, "#grant-#{grant.id}", "role address")
    assert has_element?(lv, "#team-#{team.id} li", "office@example.com")
  end

  test "keeps a person whose own key is the team key among the managers", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)
    team = team_fixture(%{d4h_access_key_member_id: 901, d4h_access_key_owner: "Kim Lee"})

    kim =
      member_fixture(team, %{
        name: "Kim Lee",
        d4h_member_id: 901,
        d4h_permission: 0,
        d4h_status: "OPERATIONAL"
      })

    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert has_element?(lv, "#manager-#{kim.id}", "Kim Lee")
  end

  test "shows when each team and contact was last seen", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)

    %{user: recent, team: team} = user_with_team_fixture()
    earlier = App.AccountsFixtures.user_fixture()
    manager_fixture(team, %{email: earlier.email})
    unused = team_fixture()

    now = DateTime.utc_now(:second)
    seen(recent, now)
    seen(earlier, DateTime.add(now, -130, :day))

    {:ok, lv, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    assert has_element?(lv, "#team-#{team.id}-last-seen", "Today")
    assert render(element(lv, "#team-#{team.id} li", earlier.email)) =~ "4 months ago"
    refute has_element?(lv, "#team-#{unused.id}-last-seen", ~r/\S/)
  end

  test "shows why a team's refresh failed", %{conn: conn} do
    %{user: admin, team: team} = user_with_team_fixture()
    admin = make_admin(admin)

    {:ok, _team} =
      Team.update(team, %{
        d4h_refresh_result: "Error: No D4H key. Save a team key in Team Settings."
      })

    {:ok, lv, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    assert has_element?(lv, "#team-#{team.id} .text-danger-1", "No D4H key.")
  end

  test "flags a team with no users", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)
    team = team_fixture()

    {:ok, lv, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    assert has_element?(lv, "#team-#{team.id}", "No users")
  end

  test "keeps a team's contacts after a refresh broadcast", %{conn: conn} do
    %{user: admin, team: team} = user_with_team_fixture()
    admin = make_admin(admin)

    {:ok, lv, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    send(lv.pid, {:team_refreshed, %{Team.get!(team.id) | d4h_refresh_result: "OK"}})

    assert has_element?(lv, "#team-#{team.id}", admin.email)
  end

  test "redirects non-admin users", %{conn: conn} do
    %{user: user} = user_with_team_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/admin")

    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "admin"
  end

  test "redirects unauthenticated users", %{conn: conn} do
    conn = get(conn, ~p"/admin")

    assert redirected_to(conn) == ~p"/login"
  end

  defp seen(user, at) do
    user
    |> Ecto.Changeset.change(%{last_seen_at: at})
    |> App.Repo.update!()
  end

  defp make_admin(user) do
    user
    |> Ecto.Changeset.change(%{is_admin: true})
    |> App.Repo.update!()
  end
end
