defmodule Web.UserLoginLinkLive do
  use Web, :live_view_narrow_layout

  alias App.Accounts

  # The emailed link opens this page and a button logs in. Mail scanners that open links
  # ahead of the reader then can't use up the single-use token.
  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_login_token(token) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "That login link is used or expired. Ask for a new one.")
          |> push_navigate(to: ~p"/login")

        {:ok, socket}

      user ->
        {:ok, assign(socket, page_title: "Log in", token: token, email: user.email)}
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">Log in</h1>
      <.form for={%{}} id="login_link_form" action={~p"/login"}>
        <input type="hidden" name="token" value={@token} />
        <p>Log in to SAR Duty as <strong>{@email}</strong>.</p>
        <.form_actions>
          <.button variant={:success}>Log in</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end
end
