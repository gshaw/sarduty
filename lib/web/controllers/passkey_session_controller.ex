defmodule Web.PasskeySessionController do
  @moduledoc """
  Logging in with a passkey (#129). The login page's hook (assets/js/passkey.js) asks
  `options` for a challenge, which this keeps in the session, has the browser sign it,
  and posts the answer to `create`. Each challenge works once: `create` takes it out of
  the session before checking anything.

  A passkey on the device itself keeps the login for 60 days, like Remember me. One used
  through a phone at another computer, or a security key, lasts until the browser
  closes, so a hall computer forgets you.
  """

  use Web, :controller

  alias App.Accounts
  alias App.Accounts.WebAuthn
  alias Web.SecurityEvent
  alias Web.UserAuth

  @challenge :passkey_challenge

  def options(conn, _params) do
    challenge = WebAuthn.authentication_challenge()
    kept = %{"bytes" => WebAuthn.encode(challenge.bytes), "issued_at" => challenge.issued_at}

    conn
    |> put_session(@challenge, kept)
    |> json(WebAuthn.request_options(challenge))
  end

  # A passkey field that isn't a form, as from a hand-made request.
  def create(conn, %{"passkey" => params}) when not is_map(params), do: refuse(conn)

  def create(conn, %{"passkey" => params}) do
    kept = get_session(conn, @challenge)
    conn = delete_session(conn, @challenge)

    with %{"bytes" => bytes, "issued_at" => issued_at} <- kept,
         {:ok, bytes} <- WebAuthn.decode(bytes),
         challenge = WebAuthn.authentication_challenge(bytes, issued_at),
         {:ok, user} <- Accounts.log_in_with_passkey(challenge, params) do
      remember? = params["attachment"] == "platform"

      SecurityEvent.record(conn, :logged_in,
        user_id: user.id,
        email_or_phone: user.email,
        data: %{
          via: "passkey",
          known_browser: UserAuth.known_browser?(conn, user),
          remember: remember?
        }
      )

      conn
      |> put_flash(:info, "Logged in as #{user.email}.")
      |> UserAuth.log_in_user(user, remember: remember?)
    else
      _ -> refuse(conn)
    end
  end

  def create(conn, _params), do: refuse(conn)

  defp refuse(conn) do
    conn
    |> put_flash(:error, "That passkey did not log you in. Try another, or use Send me a code.")
    |> redirect(to: ~p"/login")
  end
end
