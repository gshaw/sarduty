defmodule Web.UserLoginLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Accounts.UserToken
  alias App.Repo

  test "asks for an email only", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/login")

    assert has_element?(lv, "#login_form input[type=email]")
    refute has_element?(lv, "#login_form input[type=password]")
  end

  test "a login link opens a page with a button that logs in", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    {token, user_token} = UserToken.build_login_token(user)
    Repo.insert!(user_token)

    {:ok, lv, _html} = live(conn, ~p"/login/#{token}")

    assert has_element?(lv, "#login_link_form", user.email)
    assert has_element?(lv, ~s(#login_link_form input[name=token][value="#{token}"]))
  end

  test "a used or expired link goes back to the login page", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, ~p"/login/expired-token")
  end
end
