defmodule Web.PasskeySessionControllerTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import App.PasskeyFixtures

  alias App.Accounts.UserPasskey
  alias App.Accounts.WebAuthn
  alias App.Model.Event
  alias App.Repo

  # A current member, so they may log in, with a passkey.
  defp member_with_passkey do
    %{user: user, team: team} = user_with_team_fixture()
    {passkey, key} = passkey_fixture(user)
    %{user: user, team: team, passkey: passkey, key: key}
  end

  # The login page's first step: a challenge, kept in the session.
  defp options(conn) do
    conn = post(conn, ~p"/login/passkey/options")
    %{"bytes" => text, "issued_at" => issued_at} = get_session(conn, :passkey_challenge)
    {:ok, bytes} = WebAuthn.decode(text)
    {conn, WebAuthn.authentication_challenge(bytes, issued_at)}
  end

  defp log_in(conn, params), do: post(conn, ~p"/login/passkey", %{"passkey" => params})

  test "gives the browser a challenge for any passkey on this site", %{conn: conn} do
    conn = post(conn, ~p"/login/passkey/options")
    options = json_response(conn, 200)

    assert options["rpId"] == Web.Endpoint.host()
    assert options["userVerification"] == "required"
    assert options["allowCredentials"] == []
    kept = get_session(conn, :passkey_challenge)
    assert options["challenge"] == kept["bytes"]
  end

  test "logs in with a passkey on the device, remembered for 60 days", %{conn: conn} do
    %{user: user, team: team, passkey: passkey, key: key} = member_with_passkey()
    {conn, challenge} = options(conn)

    conn = log_in(conn, get_answer(key, challenge, user))

    assert redirected_to(conn) == ~p"/teams/#{team}"
    assert get_session(conn, :user_token)
    assert conn.resp_cookies["_sarduty_remember_me"]
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Logged in as #{user.email}."
    assert Repo.reload!(passkey).last_used_at

    assert %Event{user_id: user_id, data: %{"via" => "passkey", "remember" => true}} =
             Event.get_last(:logged_in)

    assert user_id == user.id
  end

  test "a passkey from a phone at another computer lasts until the browser closes",
       %{conn: conn} do
    %{user: user, key: key} = member_with_passkey()
    {conn, challenge} = options(conn)

    conn = log_in(conn, get_answer(key, challenge, user, attachment: "cross-platform"))

    assert get_session(conn, :user_token)
    refute conn.resp_cookies["_sarduty_remember_me"]
  end

  test "a challenge works once, right or wrong", %{conn: conn} do
    %{user: user, key: key} = member_with_passkey()
    {conn, challenge} = options(conn)

    wrong = log_in(conn, get_answer(authenticator(), challenge, user))
    refute get_session(wrong, :passkey_challenge)

    again = log_in(wrong, get_answer(key, challenge, user))
    assert redirected_to(again) == ~p"/login"
    refute get_session(again, :user_token)
  end

  test "refuses a passkey SAR Duty doesn't know, or one removed", %{conn: conn} do
    %{user: user, passkey: passkey} = member_with_passkey()
    {conn, challenge} = options(conn)

    conn = log_in(conn, get_answer(authenticator(), challenge, user))

    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, :user_token)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "That passkey did not log you in."

    Repo.delete!(passkey)
    refute UserPasskey.get_by_credential_id(passkey.credential_id)
  end

  test "refuses someone D4H no longer lists, passkey or not", %{conn: conn} do
    user = user_fixture()
    {_passkey, key} = passkey_fixture(user)
    {conn, challenge} = options(conn)

    conn = log_in(conn, get_answer(key, challenge, user))

    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, :user_token)
  end

  test "refuses an answer with no challenge in the session", %{conn: conn} do
    %{user: user, key: key} = member_with_passkey()
    challenge = WebAuthn.authentication_challenge()

    conn = log_in(conn, get_answer(key, challenge, user))

    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, :user_token)
  end

  test "refuses a passkey field that isn't a form, rather than crashing", %{conn: conn} do
    {conn, _challenge} = options(conn)

    conn = post(conn, ~p"/login/passkey", %{"passkey" => "x"})

    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, :user_token)
  end
end
