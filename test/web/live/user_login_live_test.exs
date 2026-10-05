defmodule Web.UserLoginLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  test "asks for an email only", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/login")

    assert has_element?(lv, "#login_form input[type=email]")
    refute has_element?(lv, "#login_form input[type=password]")
  end

  test "submitting hands the form to the controller", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/login")

    refute has_element?(lv, "#login_submit[disabled]")

    form = form(lv, "#login_form", user: %{email: "pat@example.com"})
    render_submit(form)

    # Busy until the POST below leaves the page.
    assert has_element?(lv, "#login_submit[disabled]", "Sending…")

    conn = follow_trigger_action(form, conn)
    assert redirected_to(conn) == ~p"/login/code"
  end

  test "the code page shows the email from the session, and stays on refresh", %{conn: conn} do
    conn = Phoenix.ConnTest.init_test_session(conn, %{login_email: "pat@example.com"})

    {:ok, lv, _html} = live(conn, ~p"/login/code")
    assert has_element?(lv, "#login-code", "pat@example.com")

    assert has_element?(
             lv,
             ~s(#login_code_form input[name="user[code]"][autocomplete=one-time-code])
           )

    assert has_element?(
             lv,
             ~s(#login_code_form input[name="user[remember_me]"][type=checkbox])
           )

    refute has_element?(lv, ~s(#login_code_form input[name="user[remember_me]"][checked]))

    {:ok, lv, _html} = live(conn, ~p"/login/code")
    assert has_element?(lv, "#login-code", "pat@example.com")
  end

  test "sign-up links to the code page with the email in the query", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/login/code?email=pat@example.com")

    assert has_element?(
             lv,
             ~s(#login_code_form input[name="user[email]"][value="pat@example.com"])
           )
  end

  test "submitting the code hands it to the controller", %{conn: conn} do
    conn = Phoenix.ConnTest.init_test_session(conn, %{login_email: "pat@example.com"})
    {:ok, lv, _html} = live(conn, ~p"/login/code")

    refute has_element?(lv, "#login_code_submit[disabled]")

    form = form(lv, "#login_code_form", user: %{code: "123456", remember_me: "true"})
    render_submit(form)

    assert has_element?(lv, "#login_code_form[phx-trigger-action]")
    assert has_element?(lv, "#login_code_submit[disabled]", "Logging in…")
  end

  test "the code page without an email goes to the login form", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, ~p"/login/code")
  end
end
