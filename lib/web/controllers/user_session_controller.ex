defmodule Web.UserSessionController do
  use Web, :controller

  alias App.Accounts
  alias App.Worker.NotifyLoginBlockedWorker
  alias App.Worker.SendLoginCodeWorker
  alias Web.LoginLimit
  alias Web.SecurityEvent
  alias Web.UserAuth
  alias Web.VerifyLimit

  # One field takes an email or, with text login on, a mobile number: an "@" means email.
  # The reply is the same whether or not either may log in, so the form can't be used to
  # find out who has access.
  def request_code(conn, %{"user" => %{"login" => login}}) do
    login = login |> String.trim() |> String.slice(0, 160)
    text_login? = Accounts.text_login?()

    cond do
      String.contains?(login, "@") ->
        request_email_code(conn, login)

      e164 = text_login? && Service.Phone.normalize(login) ->
        request_text_code(conn, e164)

      text_login? ->
        ask_again(
          conn,
          "Enter your email, or a mobile number with its area code, like 604-555-1234."
        )

      true ->
        ask_again(conn, "Enter your email.")
    end
  end

  defp request_email_code(conn, email) do
    if request_allowed?(conn, email), do: send_code(%{email: email})

    # The code page reads the email from the session, so a refresh shows it again rather
    # than the form.
    conn
    |> delete_session(:login_phone)
    |> put_session(:login_email, email)
    |> redirect(to: ~p"/login/code")
  end

  defp request_text_code(conn, e164) do
    if request_allowed?(conn, {:phone, e164}), do: send_code(%{phone: e164})

    conn
    |> delete_session(:login_email)
    |> put_session(:login_phone, e164)
    |> redirect(to: ~p"/login/code")
  end

  defp ask_again(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/login")
  end

  # Records each request within the limits, and the first one over them.
  defp request_allowed?(conn, who) do
    result = LoginLimit.check(who, VerifyLimit.client_ip(conn))
    data = %{via: via(who), who: SecurityEvent.who(who)}

    case result do
      :ok -> SecurityEvent.record(conn, :login_code_requested, data: data)
      :limit_reached -> SecurityEvent.record(conn, :login_code_limited, data: data)
      :limited -> :ok
    end

    result == :ok
  end

  defp via({:phone, _phone}), do: "text"
  defp via(_email), do: "email"

  # A job sends the code, or doesn't, after the reply. Sending inline made the reply a
  # few hundred ms slower for someone with access (#176).
  defp send_code(args), do: args |> SendLoginCodeWorker.new() |> Oban.insert!()

  def create(conn, %{"user" => %{"phone" => phone, "code" => code} = params}) do
    ip = VerifyLimit.client_ip(conn)
    phone = Service.Phone.normalize(phone) || ""
    known? = known_browser?(conn, Accounts.text_login?() && Accounts.text_login_email(phone))

    blocked? = LoginLimit.guessing_blocked?({:phone, phone}, ip, known?)
    result = if blocked?, do: :error, else: Accounts.log_in_with_text_code(phone, code)

    case result do
      {:ok, user} ->
        log_in(conn, user, params, {:phone, phone}, known?)

      :error ->
        count_miss(conn, {:phone, phone}, blocked?, known?, %{phone: phone})

        conn
        |> put_session(:login_phone, phone)
        |> put_flash(:error, "That code is wrong or expired. Check it, or ask for a new one.")
        |> redirect(to: ~p"/login/code")
    end
  end

  def create(conn, %{"user" => %{"email" => email, "code" => code} = params}) do
    ip = VerifyLimit.client_ip(conn)
    known? = known_browser?(conn, email)

    blocked? = LoginLimit.guessing_blocked?(email, ip, known?)
    result = if blocked?, do: :error, else: Accounts.log_in_with_code(email, code)

    case result do
      {:ok, user} ->
        log_in(conn, user, params, email, known?)

      :error ->
        count_miss(conn, email, blocked?, known?, %{email: email})

        conn
        |> put_session(:login_email, email)
        |> put_flash(:error, "That code is wrong or expired. Check it, or ask for a new one.")
        |> redirect(to: ~p"/login/code")
    end
  end

  defp known_browser?(conn, email) when is_binary(email),
    do: UserAuth.known_browser?(conn, Accounts.get_user_by_email(email))

  defp known_browser?(_conn, _no_email), do: false

  # The miss that blocks an account tells its owner, from a job like the login code.
  # Tries after a block aren't recorded, so a flood can't fill the events table; the
  # block itself is.
  defp count_miss(conn, who, blocked?, known?, args) do
    ip = VerifyLimit.client_ip(conn)
    data = %{via: via(who), who: SecurityEvent.who(who), known_browser: known?}
    blocks = LoginLimit.miss(who, ip, known?)

    unless blocked?, do: SecurityEvent.record(conn, :login_code_missed, data: data)

    for scope <- blocks do
      SecurityEvent.record(conn, :login_blocked, data: Map.put(data, :scope, scope))
    end

    if :account in blocks, do: args |> NotifyLoginBlockedWorker.new() |> Oban.insert!()
  end

  defp log_in(conn, user, params, who, known?) do
    remember? = params["remember_me"] == "true"

    SecurityEvent.record(conn, :logged_in,
      user_id: user.id,
      data: %{via: via(who), known_browser: known?, remember: remember?}
    )

    conn
    |> put_flash(:info, "Logged in as #{user.email}.")
    |> UserAuth.log_in_user(user, remember: remember?)
  end

  def delete(conn, _params) do
    if user = conn.assigns[:current_user],
      do: SecurityEvent.record(conn, :logged_out, user_id: user.id)

    conn
    |> put_flash(:info, "Logged out.")
    |> UserAuth.log_out_user()
  end
end
