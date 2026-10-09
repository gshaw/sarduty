defmodule Web.MeContactController do
  use Web, :controller

  alias App.Operation.ChangeOwnContact
  alias Web.LoginLimit
  alias Web.UserAuth
  alias Web.VerifyLimit

  # A member's code for a new email or mobile number (#156), posted from MeContactLive.
  # A controller, not the LiveView, because a new email moves the session to the user for
  # that email, and only a conn can set the session. Wrong codes count like login ones.
  def confirm(conn, %{"confirm" => %{"sent_to" => sent_to, "code" => code}}) do
    %{member: member, current_user: user} = conn.assigns
    ip = VerifyLimit.client_ip(conn)
    who = who(sent_to)

    result =
      if LoginLimit.guessing_blocked?(who, ip),
        do: {:error, :wrong_code},
        else: ChangeOwnContact.confirm(member, user, sent_to, code, DateTime.utc_now())

    case result do
      {:ok, new_user} ->
        confirmed(conn, member, ChangeOwnContact.kind(sent_to), sent_to, new_user)

      {:error, :wrong_code} ->
        wrong_code(conn, member, who, ip)

      {:error, text} ->
        conn |> put_flash(:error, text) |> redirect(to: contact_path(member))
    end
  end

  defp confirmed(conn, member, :email, _email, new_user) do
    conn
    |> put_session(:user_return_to, ~p"/teams/#{member.team}/me")
    |> put_flash(:info, "Your email is changed. Log in with it from now on.")
    |> UserAuth.log_in_user(new_user, remember: UserAuth.remembered?(conn))
  end

  defp confirmed(conn, member, :phone, e164, _user) do
    message =
      if ChangeOwnContact.shared_phone?(member, e164, DateTime.utc_now()),
        do: "Your mobile number is changed. Another member has it too, so text login won't work.",
        else: "Your mobile number is changed. Login codes by text go to it now."

    conn |> put_flash(:info, message) |> redirect(to: ~p"/teams/#{member.team}/me")
  end

  defp wrong_code(conn, member, who, ip) do
    LoginLimit.miss(who, ip)

    conn
    |> put_flash(:error, "That code is wrong or expired. Check it, or ask for a new one.")
    |> redirect(to: contact_path(member))
  end

  defp who("+" <> _digits = e164), do: {:phone, e164}
  defp who(email), do: email

  defp contact_path(member), do: ~p"/teams/#{member.team}/me/contact"
end
