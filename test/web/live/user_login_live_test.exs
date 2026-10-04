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

  test "submitting hands the form to the controller", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/login")

    form = form(lv, "#login_form", user: %{email: "pat@example.com"})
    render_submit(form)

    conn = follow_trigger_action(form, conn)
    assert redirected_to(conn) == ~p"/login/sent"
  end

  test "a login link opens a page with a button that logs in", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    {token, user_token} = UserToken.build_login_token(user)
    Repo.insert!(user_token)

    {:ok, lv, _html} = live(conn, ~p"/login/#{token}")

    assert has_element?(lv, "#login_link_form", user.email)
    assert has_element?(lv, ~s(#login_link_form input[name=token][value="#{token}"]))
  end

  test "the browser that asked for the link logs in on its own", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {token, user_token} = UserToken.build_login_token(user)
    Repo.insert!(user_token)
    conn = Phoenix.ConnTest.init_test_session(conn, %{login_link_email: user.email})

    {:ok, lv, _html} = live(conn, ~p"/login/#{token}")

    assert has_element?(lv, "#login_link_form[phx-trigger-action]")
    conn = follow_trigger_action(element(lv, "#login_link_form"), conn)
    assert redirected_to(conn) == ~p"/#{team.subdomain}"
  end

  test "another browser, like a mail scanner, gets the button only", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    {token, user_token} = UserToken.build_login_token(user)
    Repo.insert!(user_token)

    {:ok, lv, _html} = live(conn, ~p"/login/#{token}")

    refute has_element?(lv, "#login_link_form[phx-trigger-action]")
  end

  test "a used or expired link goes back to the login page", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, ~p"/login/expired-token")
  end

  test "after asking for a link, the sent page stays on refresh", %{conn: conn} do
    conn = Phoenix.ConnTest.init_test_session(conn, %{login_link_email: "pat@example.com"})

    {:ok, lv, _html} = live(conn, ~p"/login/sent")
    assert has_element?(lv, "#login-sent", "pat@example.com")
    refute has_element?(lv, "#login_form")

    {:ok, lv, _html} = live(conn, ~p"/login/sent")
    assert has_element?(lv, "#login-sent", "pat@example.com")
  end

  test "the sent page without a request goes to the login form", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, ~p"/login/sent")
  end
end
