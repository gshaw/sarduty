defmodule Web.UserLoginLive do
  use Web, :live_view_narrow_layout

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">Log in</h1>
      <p>
        Enter the email D4H has for you. If you're an Owner or Editor on your team in D4H,
        we'll email you a link to log in. There's no password.
      </p>
      <.form for={@form} id="login_form" action={~p"/login/link"} phx-update="ignore">
        <.input field={@form[:email]} type="email" label="Email" required autocomplete="email" />
        <.form_actions>
          <.button variant={:success}>Email me a login link</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    form = to_form(%{"email" => nil}, as: "user")
    {:ok, assign(socket, page_title: "Log in", form: form), temporary_assigns: [form: form]}
  end
end
