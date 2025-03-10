defmodule Web.UserLoginLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest
  import App.AccountsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")

      assert html =~ "Log in"
      # assert html =~ "Sign up"
      assert html =~ "Forgot your password?"
    end
  end

  describe "user login" do
    test "redirects if user login with valid credentials", %{conn: conn} do
      password = "123456789abcd"
      user = user_fixture(%{password: password})

      {:ok, lv, _html} = live(conn, ~p"/login")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: password, remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/login")

      form =
        form(lv, "#login_form",
          user: %{email: "test@email.com", password: "123456", remember_me: true}
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

      assert redirected_to(conn) == "/login"
    end
  end

  describe "login navigation" do
    # test "redirects to sign up page when the sign up button is clicked", %{conn: conn} do
    #   {:ok, lv, _html} = live(conn, ~p"/login")

    #   {:ok, _login_live, login_html} =
    #     lv
    #     |> element(~s|main a:fl-contains("Sign up")|)
    #     |> render_click()
    #     |> follow_redirect(conn, ~p"/signup")

    #   assert login_html =~ "Sign up"
    # end

    test "redirects to forgot password page when the Forgot Password button is clicked", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/login")

      {:ok, _lv, html} =
        lv
        |> element(~s|main a:fl-contains("Forgot your password?")|)
        |> render_click()
        |> follow_redirect(conn, ~p"/login/reset")

      assert html =~ "Forgot your password?"
    end
  end
end
