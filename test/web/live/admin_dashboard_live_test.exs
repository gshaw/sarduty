defmodule Web.AdminDashboardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team
  alias App.Model.TeamLoginGrant

  test "renders admin dashboard for admin users", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    user = make_admin(user)

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin")

    assert html =~ "Admin"
    # Plain, and asks first: no button is yellow (#995).
    assert has_element?(
             lv,
             "#refresh-all.btn:not(.btn-primary)[data-confirm^='Refresh all teams now?']"
           )
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

  test "says whose account each team key is", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)

    sar_duty = team_fixture(%{d4h_access_key: "k1", d4h_access_key_owner: "SAR Duty"})
    person = team_fixture(%{d4h_access_key: "k2", d4h_access_key_owner: "Sam Rivers"})
    no_key = team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert has_element?(lv, "#team-#{sar_duty.id}-key", "SAR Duty")
    assert has_element?(lv, "#team-#{person.id}-key", "Person's: Sam Rivers")
    assert has_element?(lv, "#team-#{no_key.id}-key", "None")
  end

  test "counts each team's team admins once per email, and None in red", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)
    team = team_fixture()
    manager_fixture(team, %{email: "owner@example.com"})
    manager_fixture(team, %{email: "editor@example.com", d4h_permission: 1})
    manager_fixture(team, %{email: "member@example.com", d4h_permission: 2})
    TeamLoginGrant.grant!(team, "owner@example.com", "also a grant")
    TeamLoginGrant.grant!(team, "office@example.com", nil)
    nobody = team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert has_element?(lv, "#team-#{team.id}-team-admins", "3")
    assert has_element?(lv, "#team-#{nobody.id}-team-admins.text-danger-text", "None")
    refute has_element?(lv, "#team-#{team.id}", "owner@example.com")
  end

  test "links each team to its admin page", %{conn: conn} do
    %{user: admin, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(make_admin(admin)) |> live(~p"/admin")
    assert has_element?(lv, ~s|#team-#{team.id}-name[href="/admin/teams/#{team.id}"]|)
  end

  test "shows when each team was last seen", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)
    %{user: recent, team: team} = user_with_team_fixture()
    unused = team_fixture()
    seen(recent, DateTime.utc_now(:second))

    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

    assert has_element?(lv, "#team-#{team.id}-last-seen", "Today")
    assert has_element?(lv, "#team-#{unused.id}-last-seen", "Never")
  end

  test "each stat switch count matches the rows its view shows", %{conn: conn} do
    %{user: admin, team: team} = user_with_team_fixture()
    admin = make_admin(admin)
    Team.update(team, %{d4h_refresh_result: "OK", d4h_refreshed_at: DateTime.utc_now()})
    failing = team_fixture(%{d4h_access_key: "k", d4h_access_key_owner: "Sam Rivers"})
    {:ok, _team} = Team.update(failing, %{d4h_refresh_result: "Error: 500"})
    nobody = team_fixture(%{d4h_refresh_result: "OK"})
    demo = team_fixture(%{name: "Coast Range SAR"})
    demo_team_fixture(demo)
    conn = log_in_user(conn, admin)
    all = [team.id, failing.id, nobody.id, demo.id]

    for {view, ids} <- [
          {"all", [team.id, failing.id, nobody.id]},
          {"needs-attention", [failing.id, nobody.id]},
          {"person-key", [failing.id]},
          {"demos", [demo.id]}
        ] do
      {:ok, lv, _html} = live(conn, ~p"/admin?view=#{view}")
      assert has_element?(lv, "#team-view-#{view}", "#{length(ids)}")
      for id <- ids, do: assert(has_element?(lv, "#team-#{id}"))
      for id <- all -- ids, do: refute(has_element?(lv, "#team-#{id}"))
    end
  end

  test "a demo's row says whose it is and when it goes", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    visitor = team_fixture(%{name: "Coast Range SAR", timezone: "America/Toronto"})
    test_demo = team_fixture(%{name: "Coast Range SAR", timezone: "America/Toronto"})
    goes = ~U[2026-11-09 19:17:00Z]

    visitor
    |> demo_team_fixture()
    |> Ecto.Changeset.change(expires_at: goes)
    |> App.Repo.update!()

    test_demo
    |> demo_team_fixture(%{kind: :test, name: nil})
    |> Ecto.Changeset.change(expires_at: goes)
    |> App.Repo.update!()

    {:ok, lv, _html} = conn |> log_in_user(make_admin(admin)) |> live(~p"/admin?view=demos")

    assert has_element?(
             lv,
             "#team-#{visitor.id}-demo",
             "Visitor, Morgan Visitor · goes Nov 9, 14:17"
           )

    assert has_element?(lv, "#team-#{test_demo.id}-demo", "Test · goes Nov 9, 14:17")
  end

  test "an unknown view, such as an old link, falls back to Teams", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(make_admin(admin)) |> live(~p"/admin?view=mcp-on")
    assert has_element?(lv, "#team-view-all[aria-current=page]")
  end

  test "a refresh broadcast updates the team's row", %{conn: conn} do
    %{user: admin, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(make_admin(admin)) |> live(~p"/admin")

    send(lv.pid, {:team_refreshed, %{Team.get!(team.id) | d4h_refresh_result: "OK"}})

    assert has_element?(lv, "#team-#{team.id}-refresh", "OK")
  end

  test "is a 404 for anyone who isn't a SAR Duty admin (#513)", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    conn = log_in_user(conn, user)

    for path <- ["/admin", "/admin/orgs", "/admin/events", "/admin/teams/1"] do
      assert_error_sent 404, fn -> get(conn, path) end
    end
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
end
