defmodule Web.UserLoginLive do
  use Web, :live_view_narrow_layout

  alias App.Accounts

  # The submit goes through LiveView first so the button disables at once, then
  # phx-trigger-action posts the form to the controller, which sends the code. The button
  # stays busy until that POST leaves the page. With Twilio set up, the one field takes an
  # email or a mobile number, and the controller tells them apart.
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">Log in</h1>
      <p :if={@text_login}>
        Enter the email or mobile number D4H has for you. If you may log in, we'll send you a
        code. There's no password.
      </p>
      <p :if={not @text_login}>
        Enter the email D4H has for you. If you may log in, we'll email you a code. There's
        no password.
      </p>
      <p class="hint">
        Team admins can log in. Members can too, when their team turns on member logins.
      </p>
      <.form
        for={@form}
        id="login_form"
        action={~p"/login/code"}
        phx-submit="submit"
        phx-trigger-action={@trigger_submit}
      >
        <.input
          :if={@text_login}
          field={@form[:login]}
          type="text"
          label="Email or mobile number"
          required
          autocomplete="username"
          autocapitalize="none"
          spellcheck="false"
        >
          For a mobile number, include the area code, like 604-555-1234.
        </.input>
        <.input
          :if={not @text_login}
          field={@form[:login]}
          type="email"
          label="Email"
          required
          autocomplete="email"
        />
        <.form_actions>
          <.button
            id="login_submit"
            variant={:success}
            disabled={@trigger_submit}
            phx-disable-with="Sending…"
          >
            {if @trigger_submit, do: "Sending…", else: "Send me a code"}
          </.button>
        </.form_actions>
      </.form>
      <p class="text-text-muted">
        Team not on SAR Duty yet?
        <.a navigate={~p"/signup"}>Sign up your team</.a>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Log in",
       text_login: Accounts.text_login?(),
       form: to_form(%{"login" => nil}, as: "user"),
       trigger_submit: false
     )}
  end

  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
