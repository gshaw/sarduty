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

  test "lists each team's users and links an email to all of them", %{conn: conn} do
    %{user: admin} = user_with_team_fixture()
    admin = make_admin(admin)

    %{user: with_key, team: team} = user_with_team_fixture()
    without_key = App.AccountsFixtures.user_fixture()
    {:ok, without_key} = User.update(without_key, %{team_id: team.id})

    {:ok, lv, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    row = "#team-#{team.id}"
    [first, second] = Enum.sort([with_key.email, without_key.email])

    assert render(element(lv, row)) =~ with_key.email
    assert render(element(lv, row)) =~ without_key.email
    assert has_element?(lv, "#{row} .badge", "D4H key")
    assert has_element?(lv, ~s(#{row} a[href="mailto:#{first},#{second}"]), "Email")
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
    refute has_element?(lv, "#team-#{team.id} a[href^='mailto:']")
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
