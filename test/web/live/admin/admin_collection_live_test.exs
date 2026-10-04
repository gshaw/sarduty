defmodule Web.Admin.AdminCollectionLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "lists every admin, and not other users", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    admin = make_admin(user)
    other_admin = make_admin(user_fixture())
    not_admin = user_fixture()

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/admins")

    assert has_element?(lv, "#admin-#{admin.id}")
    assert has_element?(lv, "#admin-#{other_admin.id}", other_admin.email)
    refute has_element?(lv, "#admin-#{not_admin.id}")
    assert has_element?(lv, "#nav-admin[aria-current=page]")
  end

  test "is for admins only", %{conn: conn} do
    %{user: user} = user_with_team_fixture()

    assert {:error, {:redirect, _}} = live(log_in_user(conn, user), ~p"/admin/admins")
  end
end
