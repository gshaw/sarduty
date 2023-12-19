defmodule Web.UserLoginLive do
  use Web, :live_view_narrow

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">Log in</h1>
      <p>
        Don't have an account?
        <.a navigate="/signup">Sign up</.a>
      </p>

      <.form for={@form} id="login_form" action={~p"/login"} phx-update="ignore">
        <.input field={@form[:email]} type="email" label="Email" required phx-debounce />
        <.input field={@form[:password]} type="password" label="Password" required phx-debounce>
          <.a navigate={~p"/login/reset"} class="link">Forgot your password?</.a>
        </.input>

        <.input type="checkbox" field={@form[:remember_me]} label="Remember Me">
          Saves information on this browser so you don't have to log in again for 60 days.
        </.input>

        <.form_actions>
          <.button class="btn-success">Log in</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = live_flash(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    socket =
      assign(socket,
        page_title: "Log in",
        form: form
      )

    {:ok, socket, temporary_assigns: [form: form]}
  end
end
