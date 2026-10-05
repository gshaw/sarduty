defmodule Web.UserSessionControllerTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Accounts.UserToken

  defp request_code(conn, email),
    do: post(conn, ~p"/login/code", %{"user" => %{"email" => email}})

  defp log_in(conn, email, code, extra \\ %{}),
    do: post(conn, ~p"/login", %{"user" => Map.merge(%{"email" => email, "code" => code}, extra)})

  defp wrong(code), do: if(code == "000000", do: "111111", else: "000000")

  describe "POST /login/code" do
    test "emails a manager a code, and says the same as for anyone", %{conn: conn} do
      manager_fixture(team_fixture(), %{email: "pat@example.com"})

      conn = request_code(conn, "pat@example.com")

      assert redirected_to(conn) == ~p"/login/code"
      assert get_session(conn, :login_email) == "pat@example.com"
      assert_received {:email, %{subject: "Your SAR Duty login code: " <> _}}
    end

    test "sends nothing to an email that may not log in, with the same reply", %{conn: conn} do
      conn = request_code(conn, "stranger@example.com")

      assert redirected_to(conn) == ~p"/login/code"
      assert get_session(conn, :login_email) == "stranger@example.com"
      refute_received {:email, _}
    end

    test "stops sending after 5 requests for one email", %{conn: conn} do
      manager_fixture(team_fixture(), %{email: "busy@example.com"})

      # Clear each code, so the one-a-minute rule doesn't hide the cap.
      for _ <- 1..6 do
        request_code(conn, "busy@example.com")
        App.Repo.delete_all(UserToken)
      end

      assert length(sent_emails()) == 5
    end
  end

  describe "POST /login" do
    test "logs in with the right code, once, and remembers the login", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      code = login_code_fixture(user.email)

      conn = log_in(conn, user.email, code)
      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/#{team.subdomain}"
      assert conn.resp_cookies["_sarduty_remember_me"]

      conn = log_in(build_conn(), user.email, code)
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "wrong or expired"
    end

    test "on a shared computer, sets no remember-me cookie", %{conn: conn} do
      %{user: user} = user_with_team_fixture()
      code = login_code_fixture(user.email)

      conn = log_in(conn, user.email, code, %{"shared_computer" => "true"})

      assert get_session(conn, :user_token)
      refute conn.resp_cookies["_sarduty_remember_me"]
    end

    test "returns to the page that asked for a login", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      code = login_code_fixture(user.email)

      conn = get(conn, ~p"/#{team.subdomain}/members")
      assert redirected_to(conn) == ~p"/login"

      conn = conn |> recycle() |> log_in(user.email, code)
      assert redirected_to(conn) == ~p"/#{team.subdomain}/members"
    end

    test "a wrong code goes back to the code page, keeping the email", %{conn: conn} do
      %{user: user} = user_with_team_fixture()
      code = login_code_fixture(user.email)

      conn = log_in(conn, user.email, wrong(code))

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/login/code"
      assert get_session(conn, :login_email) == user.email
    end

    test "after 20 wrong codes in a day, even the right one fails", %{conn: conn} do
      %{user: user} = user_with_team_fixture()

      for _ <- 1..4 do
        code = login_code_fixture(user.email)
        for _ <- 1..5, do: log_in(conn, user.email, wrong(code))
        App.Repo.delete_all(UserToken)
      end

      code = login_code_fixture(user.email)
      conn = log_in(conn, user.email, code)
      refute get_session(conn, :user_token)
    end

    test "the login form sends someone already logged in to their team", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      conn = conn |> log_in_user(user) |> get(~p"/login")
      assert redirected_to(conn) == ~p"/#{team.subdomain}"
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
