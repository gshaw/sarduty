defmodule Web.UserLoginLive do
  use Web, :live_view_narrow_layout

  # The submit goes through LiveView first so the button disables at once, then
  # phx-trigger-action posts the form to the controller, which sends the link.
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">Log in</h1>
      <p>
        Enter the email D4H has for you. If you're an Owner or Editor on your team in D4H,
        we'll email you a link to log in. There's no password.
      </p>
      <.form
        for={@form}
        id="login_form"
        action={~p"/login/link"}
        phx-submit="submit"
        phx-trigger-action={@trigger_submit}
      >
        <.input field={@form[:email]} type="email" label="Email" required autocomplete="email" />
        <.form_actions>
          <.button variant={:success} phx-disable-with="Sending…">Email me a login link</.button>
        </.form_actions>
      </.form>
      <p class="text-secondary-1">
        Team not on SAR Duty yet?
        <.a navigate={~p"/signup"}>Sign up your team</.a>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    form = to_form(%{"email" => nil}, as: "user")
    {:ok, assign(socket, page_title: "Log in", form: form, trigger_submit: false)}
  end

  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
