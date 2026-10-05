defmodule Web.UserLoginLive do
  use Web, :live_view_narrow_layout

  alias App.Accounts

  # The submit goes through LiveView first so the button disables at once, then
  # phx-trigger-action posts the form to the controller, which sends the code. The button
  # stays busy until that POST leaves the page. With Twilio set up, `?with=phone` asks for
  # a mobile number instead of an email.
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">Log in</h1>
      <%= if @with_phone do %>
        <p>
          Enter the mobile number D4H has for you. If you're an Owner or Editor on your team
          in D4H, we'll text you a code to log in. There's no password.
        </p>
        <.form
          for={@form}
          id="login_phone_form"
          action={~p"/login/code"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            field={@form[:phone]}
            type="tel"
            label="Mobile number"
            required
            autocomplete="tel"
          >
            Include the area code, like 604-555-1234.
          </.input>
          <.form_actions>
            <.button
              id="login_phone_submit"
              variant={:success}
              disabled={@trigger_submit}
              phx-disable-with="Sending…"
            >
              {if @trigger_submit, do: "Sending…", else: "Text me a code"}
            </.button>
          </.form_actions>
        </.form>
        <p>
          <.a id="login-with-email" navigate={~p"/login"}>Get a code by email instead</.a>
        </p>
      <% else %>
        <p>
          Enter the email D4H has for you. If you're an Owner or Editor on your team in D4H,
          we'll email you a code to log in. There's no password.
        </p>
        <.form
          for={@form}
          id="login_form"
          action={~p"/login/code"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
        >
          <.input field={@form[:email]} type="email" label="Email" required autocomplete="email" />
          <.form_actions>
            <.button
              id="login_submit"
              variant={:success}
              disabled={@trigger_submit}
              phx-disable-with="Sending…"
            >
              {if @trigger_submit, do: "Sending…", else: "Email me a code"}
            </.button>
          </.form_actions>
        </.form>
        <p :if={@text_login}>
          <.a id="login-with-phone" navigate={~p"/login?with=phone"}>
            Get a code by text message instead
          </.a>
        </p>
      <% end %>
      <p class="text-secondary-1">
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
       trigger_submit: false
     )}
  end

  def handle_params(params, _uri, socket) do
    with_phone = socket.assigns.text_login and params["with"] == "phone"
    field = if with_phone, do: "phone", else: "email"

    {:noreply, assign(socket, with_phone: with_phone, form: to_form(%{field => nil}, as: "user"))}
  end

  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
