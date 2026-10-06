defmodule Web.UserSessionController do
  use Web, :controller

  alias App.Accounts
  alias App.Worker.SendLoginCodeWorker
  alias Web.LoginLimit
  alias Web.UserAuth
  alias Web.VerifyLimit

  # The reply is the same whether or not the number may log in. With text login off,
  # nothing is sent and the email form comes back.
  def request_code(conn, %{"user" => %{"phone" => phone}}) do
    case Accounts.text_login?() && Service.Phone.normalize(phone) do
      false ->
        redirect(conn, to: ~p"/login")

      e164 when is_binary(e164) ->
        if LoginLimit.allow?({:phone, e164}, VerifyLimit.client_ip(conn)) do
          send_code(%{phone: e164})
        end

        conn
        |> delete_session(:login_email)
        |> put_session(:login_phone, e164)
        |> redirect(to: ~p"/login/code")

      nil ->
        conn
        |> put_flash(:error, "Enter your mobile number with its area code, like 604-555-1234.")
        |> redirect(to: ~p"/login?with=phone")
    end
  end

  # The reply is the same whether or not the email may log in, so the form can't be
  # used to find out who has access.
  def request_code(conn, %{"user" => %{"email" => email}}) do
    email = email |> String.trim() |> String.slice(0, 160)

    if email != "" and LoginLimit.allow?(email, VerifyLimit.client_ip(conn)) do
      send_code(%{email: email})
    end

    # The code page reads the email from the session, so a refresh shows it again rather
    # than the form.
    conn
    |> delete_session(:login_phone)
    |> put_session(:login_email, email)
    |> redirect(to: ~p"/login/code")
  end

  # A job sends the code, or doesn't, after the reply. Sending inline made the reply a
  # few hundred ms slower for someone with access (#176).
  defp send_code(args), do: args |> SendLoginCodeWorker.new() |> Oban.insert!()

  def create(conn, %{"user" => %{"phone" => phone, "code" => code} = params}) do
    ip = VerifyLimit.client_ip(conn)
    phone = Service.Phone.normalize(phone) || ""

    result =
      if LoginLimit.guessing_blocked?({:phone, phone}, ip),
        do: :error,
        else: Accounts.log_in_with_text_code(phone, code)

    case result do
      {:ok, user} ->
        log_in(conn, user, params)

      :error ->
        LoginLimit.miss({:phone, phone}, ip)

        conn
        |> put_session(:login_phone, phone)
        |> put_flash(:error, "That code is wrong or expired. Check it, or ask for a new one.")
        |> redirect(to: ~p"/login/code")
    end
  end

  def create(conn, %{"user" => %{"email" => email, "code" => code} = params}) do
    ip = VerifyLimit.client_ip(conn)

    result =
      if LoginLimit.guessing_blocked?(email, ip),
        do: :error,
        else: Accounts.log_in_with_code(email, code)

    case result do
      {:ok, user} ->
        log_in(conn, user, params)

      :error ->
        LoginLimit.miss(email, ip)

        conn
        |> put_session(:login_email, email)
        |> put_flash(:error, "That code is wrong or expired. Check it, or ask for a new one.")
        |> redirect(to: ~p"/login/code")
    end
  end

  defp log_in(conn, user, params) do
    conn
    |> put_flash(:info, "Logged in as #{user.email}.")
    |> UserAuth.log_in_user(user, remember: params["remember_me"] == "true")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out.")
    |> UserAuth.log_out_user()
  end
end
