defmodule Web.UserSessionController do
  use Web, :controller

  alias App.Accounts
  alias Web.LoginLimit
  alias Web.UserAuth
  alias Web.VerifyLimit

  # The reply is the same whether or not the email may log in, so the form can't be
  # used to find out who has access.
  def request_code(conn, %{"user" => %{"email" => email}}) do
    email = email |> String.trim() |> String.slice(0, 160)

    if email != "" and LoginLimit.allow?(email, VerifyLimit.client_ip(conn)) do
      Accounts.deliver_login_code(email)
    end

    # The code page reads the email from the session, so a refresh shows it again rather
    # than the form.
    conn
    |> put_session(:login_email, email)
    |> redirect(to: ~p"/login/code")
  end

  def create(conn, %{"user" => %{"email" => email, "code" => code} = params}) do
    ip = VerifyLimit.client_ip(conn)

    result =
      if LoginLimit.guessing_blocked?(email, ip),
        do: :error,
        else: Accounts.log_in_with_code(email, code)

    case result do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Logged in as #{user.email}.")
        |> UserAuth.log_in_user(user, remember: params["shared_computer"] != "true")

      :error ->
        LoginLimit.miss(email, ip)

        conn
        |> put_session(:login_email, email)
        |> put_flash(:error, "That code is wrong or expired. Check it, or ask for a new one.")
        |> redirect(to: ~p"/login/code")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out.")
    |> UserAuth.log_out_user()
  end
end
