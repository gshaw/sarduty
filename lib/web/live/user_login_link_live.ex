defmodule Web.UserLoginLinkLive do
  use Web, :live_view_narrow_layout

  alias App.Accounts

  # The emailed link opens this page. Opened in the browser that asked for the link (its
  # session holds that email), it logs in on its own once connected. Anywhere else it
  # waits for the button: mail scanners open links, and some run scripts, and they must
  # not use up the single-use token.
  def mount(%{"token" => token}, session, socket) do
    case Accounts.get_user_by_login_token(token) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "That login link is used or expired. Ask for a new one.")
          |> push_navigate(to: ~p"/login")

        {:ok, socket}

      user ->
        same_browser = session["login_link_email"] == user.email

        {:ok,
         assign(socket,
           page_title: "Log in",
           token: token,
           email: user.email,
           auto: same_browser,
           trigger_submit: same_browser and connected?(socket)
         )}
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">Log in</h1>
      <.form
        for={%{}}
        id="login_link_form"
        action={~p"/login"}
        phx-trigger-action={@trigger_submit}
      >
        <input type="hidden" name="token" value={@token} />
        <p :if={@auto}>Logging you in to SAR Duty as <strong>{@email}</strong>…</p>
        <p :if={!@auto}>Log in to SAR Duty as <strong>{@email}</strong>.</p>
        <.form_actions>
          <.button variant={:success}>Log in</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end
end
