defmodule Web.UserSessionControllerTest do
  use Web.ConnCase
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Accounts.UserToken
  alias App.Model.Event
  alias App.Repo
  alias App.Worker.SendLoginCodeWorker

  defp request_code(conn, email),
    do: post(conn, ~p"/login/code", %{"user" => %{"email" => email}})

  defp log_in(conn, email, code, extra \\ %{}),
    do: post(conn, ~p"/login", %{"user" => Map.merge(%{"email" => email, "code" => code}, extra)})

  defp request_text(conn, phone),
    do: post(conn, ~p"/login/code", %{"user" => %{"phone" => phone}})

  # A client IP of the test's own, so the per-IP cap other tests use up hides nothing.
  defp from_ip(conn),
    do: put_req_header(conn, "fly-client-ip", "test-#{System.unique_integer([:positive])}")

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

    test "queues a job and sends nothing inline, with or without access", %{conn: conn} do
      manager_fixture(team_fixture(), %{email: "pat@example.com"})

      Oban.Testing.with_testing_mode(:manual, fn ->
        request_code(conn, "pat@example.com")
        request_code(conn, "stranger@example.com")

        refute_received {:email, _}
        refute Repo.exists?(UserToken)
        assert_enqueued(worker: SendLoginCodeWorker, args: %{email: "pat@example.com"})
        assert_enqueued(worker: SendLoginCodeWorker, args: %{email: "stranger@example.com"})
      end)
    end

    test "stops sending after 5 requests for one email", %{conn: conn} do
      manager_fixture(team_fixture(), %{email: "busy@example.com"})

      # Clear each code, so the one-a-minute rule doesn't hide the cap.
      for _ <- 1..6 do
        request_code(conn, "busy@example.com")
        Repo.delete_all(UserToken)
      end

      assert length(sent_emails()) == 5
    end
  end

  describe "POST /login" do
    test "logs in with the right code, once, without a remember-me cookie", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      code = login_code_fixture(user.email)

      conn = log_in(conn, user.email, code)
      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/teams/#{team}"
      refute conn.resp_cookies["_sarduty_remember_me"]

      conn = log_in(build_conn(), user.email, code)
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "wrong or expired"
    end

    test "with remember me ticked, sets the remember-me cookie", %{conn: conn} do
      %{user: user} = user_with_team_fixture()
      code = login_code_fixture(user.email)

      conn = log_in(conn, user.email, code, %{"remember_me" => "true"})

      assert get_session(conn, :user_token)
      assert conn.resp_cookies["_sarduty_remember_me"]
    end

    test "returns to the page that asked for a login", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      code = login_code_fixture(user.email)

      conn = get(conn, ~p"/teams/#{team}/members")
      assert redirected_to(conn) == ~p"/login"

      conn = conn |> recycle() |> log_in(user.email, code)
      assert redirected_to(conn) == ~p"/teams/#{team}/members"
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
        Repo.delete_all(UserToken)
      end

      code = login_code_fixture(user.email)
      conn = log_in(conn, user.email, code)
      refute get_session(conn, :user_token)

      # The owner hears about it, once.
      assert_received {:email, %{subject: "Wrong login codes entered" <> _, to: [{_, email}]}}
      assert email == user.email
      refute_received {:email, %{subject: "Wrong login codes entered" <> _}}
    end

    test "a browser that logged in before isn't locked out by someone else's wrong codes",
         %{conn: conn} do
      %{user: user} = user_with_team_fixture()
      first = log_in(conn, user.email, login_code_fixture(user.email))
      known = first.resp_cookies["_sarduty_known_browser"].value

      for _ <- 1..4 do
        code = login_code_fixture(user.email)
        for _ <- 1..5, do: build_conn() |> from_ip() |> log_in(user.email, wrong(code))
        Repo.delete_all(UserToken)
      end

      code = login_code_fixture(user.email)
      stranger = build_conn() |> from_ip() |> log_in(user.email, code)
      refute get_session(stranger, :user_token)

      Repo.delete_all(UserToken)
      code = login_code_fixture(user.email)

      mine =
        build_conn()
        |> from_ip()
        |> put_req_cookie("_sarduty_known_browser", known)
        |> log_in(user.email, code)

      assert get_session(mine, :user_token)
    end

    test "a made-up known-browser cookie doesn't count", %{conn: conn} do
      %{user: user} = user_with_team_fixture()

      for _ <- 1..4 do
        code = login_code_fixture(user.email)
        for _ <- 1..5, do: build_conn() |> from_ip() |> log_in(user.email, wrong(code))
        Repo.delete_all(UserToken)
      end

      code = login_code_fixture(user.email)
      # The cookie's term, unsigned.
      forged = [user.id] |> :erlang.term_to_binary() |> Base.encode64()

      conn =
        conn
        |> from_ip()
        |> put_req_cookie("_sarduty_known_browser", forged)
        |> log_in(user.email, code)

      refute get_session(conn, :user_token)
    end

    test "the login form sends someone already logged in to their team", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      conn = conn |> log_in_user(user) |> get(~p"/login")
      assert redirected_to(conn) == ~p"/teams/#{team}"
    end
  end

  describe "text login" do
    test "is off without Twilio: a number goes back to the email form", %{conn: conn} do
      manager_fixture(team_fixture(), %{email: "pat@example.com", phone: "604-555-1234"})

      conn = conn |> from_ip() |> request_text("604-555-1234")

      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :login_phone)
      refute_received {:text, _, _}
    end

    test "is off without Twilio: a texted code can't log in", %{conn: conn} do
      conn =
        post(conn, ~p"/login", %{"user" => %{"phone" => "+16045551234", "code" => "123456"}})

      refute get_session(conn, :user_token)
    end

    test "texts a manager a code, and says the same as for anyone", %{conn: conn} do
      text_login_fixture()
      manager_fixture(team_fixture(), %{email: "pat@example.com", phone: "604-555-1234"})

      conn = conn |> from_ip() |> request_text("(604) 555-1234")
      assert redirected_to(conn) == ~p"/login/code"
      assert get_session(conn, :login_phone) == "+16045551234"
      assert_received {:text, "+16045551234", _body}

      conn = build_conn() |> from_ip() |> request_text("604-555-9999")
      assert redirected_to(conn) == ~p"/login/code"
      assert get_session(conn, :login_phone) == "+16045559999"
      refute_received {:text, _, _}
    end

    test "asks again for what isn't a number", %{conn: conn} do
      text_login_fixture()

      conn = conn |> from_ip() |> request_text("555-1234")

      assert redirected_to(conn) == ~p"/login?with=phone"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "area code"
    end

    test "stops texting after 3 requests for one number", %{conn: conn} do
      text_login_fixture()
      manager_fixture(team_fixture(), %{email: "busy@example.com", phone: "604-555-7777"})
      conn = from_ip(conn)

      for _ <- 1..4 do
        request_text(conn, "604-555-7777")
        Repo.delete_all(UserToken)
      end

      assert length(sent_texts()) == 3
    end

    test "logs in with the texted code", %{conn: conn} do
      text_login_fixture()
      team = team_fixture()
      manager_fixture(team, %{email: "pat@example.com", phone: "604-555-1234"})
      code = text_code_fixture("+16045551234")

      conn =
        post(conn, ~p"/login", %{"user" => %{"phone" => "+16045551234", "code" => code}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/teams/#{team}"
    end

    test "a wrong code goes back to the code page, keeping the number", %{conn: conn} do
      text_login_fixture()
      manager_fixture(team_fixture(), %{email: "pat@example.com", phone: "604-555-1234"})
      code = text_code_fixture("+16045551234")

      conn =
        post(conn, ~p"/login", %{"user" => %{"phone" => "+16045551234", "code" => wrong(code)}})

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/login/code"
      assert get_session(conn, :login_phone) == "+16045551234"
    end
  end

  describe "DELETE /logout" do
    test "logs the user out", %{conn: conn} do
      user = user_fixture()
      conn = conn |> log_in_user(user) |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert %Event{user_id: user_id} = Event.get_last(:logged_out)
      assert user_id == user.id
    end
  end

  describe "security events" do
    test "a request, a login, and their IP and browser, without the email",
         %{conn: conn} do
      %{user: user} = user_with_team_fixture()
      conn = conn |> from_ip() |> put_req_header("user-agent", "Firefox/131")
      [ip] = get_req_header(conn, "fly-client-ip")

      request_code(conn, user.email)
      code = login_code_fixture(user.email)
      log_in(conn, user.email, code, %{"remember_me" => "true"})

      who = Event.who(user.email)
      assert who == Event.who(" " <> String.upcase(user.email))
      refute who =~ "@"

      assert %Event{ip: ^ip, user_agent: "Firefox/131", data: %{"via" => "email", "who" => ^who}} =
               Event.get_last(:login_code_requested)

      assert %Event{ip: ^ip, data: %{"remember" => true, "known_browser" => false}} =
               logged_in = Event.get_last(:logged_in)

      assert logged_in.user_id == user.id
    end

    test "records the first request over the limit, and none after", %{conn: conn} do
      email = "flood-#{System.unique_integer([:positive])}@example.com"
      for _ <- 1..8, do: conn |> from_ip() |> request_code(email)

      who = Event.who(email)
      since = DateTime.add(DateTime.utc_now(), -1, :minute)
      assert Event.count_since(:login_code_requested, since, %{who: who}) == 5
      assert Event.count_since(:login_code_limited, since, %{who: who}) == 1
    end

    test "records wrong codes until the block, then the block, then nothing", %{conn: conn} do
      email = "guess-#{System.unique_integer([:positive])}@example.com"
      user_fixture(%{email: email})

      for _ <- 1..22, do: conn |> from_ip() |> log_in(email, "000000")

      who = Event.who(email)
      since = DateTime.add(DateTime.utc_now(), -1, :minute)
      assert Event.count_since(:login_code_missed, since, %{who: who}) == 20

      assert Event.count_since(:login_blocked, since, %{who: who, scope: "account"}) == 1
    end
  end

  defp sent_texts(acc \\ []) do
    receive do
      {:text, _to, body} -> sent_texts([body | acc])
    after
      0 -> acc
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
