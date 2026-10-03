defmodule Web.UserSessionControllerTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Accounts.UserToken

  defp request_link(conn, email),
    do: post(conn, ~p"/login/link", %{"user" => %{"email" => email}})

  describe "POST /login/link" do
    test "emails a manager a link, and says the same as for anyone", %{conn: conn} do
      manager_fixture(team_fixture(), %{email: "pat@example.com"})

      conn = request_link(conn, "pat@example.com")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If pat@example.com can use SAR Duty"
      assert_received {:email, %{subject: "Log in to SAR Duty", text_body: body}}
      assert body =~ "/login/"
    end

    test "sends nothing to an email that may not log in, with the same reply", %{conn: conn} do
      conn = request_link(conn, "stranger@example.com")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If stranger@example.com can use"
      refute_received {:email, _}
    end

    test "stops sending after 5 requests for one email", %{conn: conn} do
      manager_fixture(team_fixture(), %{email: "busy@example.com"})

      for _ <- 1..6, do: request_link(conn, "busy@example.com")

      assert length(sent_emails()) == 5
    end
  end

  describe "POST /login" do
    test "logs in with a valid token, once", %{conn: conn} do
      %{user: user} = user_with_team_fixture()
      {token, user_token} = UserToken.build_login_token(user)
      App.Repo.insert!(user_token)

      conn = post(conn, ~p"/login", %{"token" => token})
      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert conn.resp_cookies["_sarduty_remember_me"]

      conn = post(build_conn(), ~p"/login", %{"token" => token})
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "used or expired"
    end

    test "refuses a bad token", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"token" => "nope"})

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "DELETE /logout" do
    test "logs the user out", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end

  defp sent_emails(acc \\ []) do
    receive do
      {:email, email} -> sent_emails([email | acc])
    after
      0 -> acc
    end
  end
end
