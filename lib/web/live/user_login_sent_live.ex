defmodule Web.UserLoginSentLive do
  use Web, :live_view_narrow_layout

  # Shown after asking for a login link. The email comes from the session, so a refresh
  # keeps this page instead of showing the form again.
  def mount(_params, session, socket) do
    case session["login_link_email"] do
      nil -> {:ok, push_navigate(socket, to: ~p"/login")}
      email -> {:ok, assign(socket, page_title: "Check your email", email: email)}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="login-sent">
      <h1 class="heading">Check your email</h1>
      <p>
        If <strong>{@email}</strong> can use SAR Duty, we've sent it a link to log in.
        Open the email "Log in to SAR Duty" and select the link. It works once, for 15 minutes.
      </p>
      <p class="text-secondary-1">
        Nothing after a few minutes? Check your spam folder. Only Owners and Editors on a team
        in D4H get a link, at the email D4H has for them.
      </p>
      <p :if={Web.Layouts.dev_mailbox?()} id="login-dev-mailbox">
        In development the email is in the <.a href="/dev/mailbox" external={true}>local mailbox</.a>.
      </p>
      <p>
        <.a id="login-again" navigate={~p"/login"}>Use a different email</.a>
      </p>
    </div>
    """
  end
end
