defmodule Web.AdminDashboardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Accounts.User
  alias App.Model.Team

  test "renders admin dashboard for admin users", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    user = make_admin(user)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin")

    assert html =~ "Admin"
  end

  test "lists each team's users and marks the key the refresh borrows", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)

    %{user: borrowed, team: team} = user_with_team_fixture()
    second_key = App.AccountsFixtures.user_fixture()
    {:ok, second_key} = User.update(second_key, %{team_id: team.id, d4h_access_key: "key-2"})
    without_key = App.AccountsFixtures.user_fixture()
    {:ok, without_key} = User.update(without_key, %{team_id: team.id})

    {:ok, lv, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    row = "#team-#{team.id}"

    assert has_element?(lv, "#{row} li", without_key.email)
    assert has_element?(lv, "#{row} li", borrowed.email)
    assert render(element(lv, "#{row} li", borrowed.email)) =~ "Refresh key"
    assert render(element(lv, "#{row} li", second_key.email)) =~ "D4H key"
    refute has_element?(lv, "#{row} a[href^='mailto:']")
    assert has_element?(lv, "#key-notes", "Refresh key")
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

  defp make_admin(user) do
    user
    |> Ecto.Changeset.change(%{is_admin: true})
    |> App.Repo.update!()
  end
end
