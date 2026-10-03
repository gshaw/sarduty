defmodule Web.UserSessionController do
  use Web, :controller

  alias App.Accounts
  alias Web.LoginLimit
  alias Web.UserAuth
  alias Web.VerifyLimit

  # The reply is the same whether or not the email may log in, so the form can't be
  # used to find out who has access.
  def request_link(conn, %{"user" => %{"email" => email}}) do
    email = email |> String.trim() |> String.slice(0, 160)

    if email != "" and LoginLimit.allow?(email, VerifyLimit.client_ip(conn)) do
      Accounts.deliver_login_link(email, &url(~p"/login/#{&1}"))
    end

    conn
    |> put_flash(
      :info,
      "If #{email} can use SAR Duty, a login link is on its way. It works for 15 minutes."
    )
    |> redirect(to: ~p"/login")
  end

  def create(conn, %{"token" => token}) do
    case Accounts.log_in_with_token(token) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user)

      :error ->
        conn
        |> put_flash(:error, "That login link is used or expired. Ask for a new one.")
        |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You are now logged out")
    |> UserAuth.log_out_user()
  end
end
