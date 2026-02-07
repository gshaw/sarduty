defmodule Web.AdminDashboardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders admin dashboard for admin users", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    user = make_admin(user)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/admin")

    assert html =~ "Admin"
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
