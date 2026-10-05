defmodule Web.UserLoginCodeLive do
  use Web, :live_view_narrow_layout

  alias App.Adapter.Twilio

  # Shown after asking for a code. The email or number comes from the session, so a
  # refresh keeps this page; sign-up links here with the email in the query instead. Like
  # the login form, the submit goes through LiveView, then posts to the controller, which
  # logs in. The button stays busy until that POST leaves the page.
  def mount(params, session, socket) do
    case {session["login_phone"], session["login_email"] || params["email"]} do
      {nil, nil} ->
        {:ok, push_navigate(socket, to: ~p"/login")}

      {nil, email} ->
        {:ok, assign_form(socket, "email", email)}

      {phone, _email} ->
        {:ok, assign_form(socket, "phone", phone)}
    end
  end

  defp assign_form(socket, field, value) do
    form = to_form(%{field => value, "code" => nil, "remember_me" => "false"}, as: "user")

    assign(socket,
      page_title: "Enter your code",
      field: field,
      value: value,
      form: form,
      trigger_submit: false
    )
  end

  def render(assigns) do
    ~H"""
    <div id="login-code">
      <h1 class="heading">Enter your code</h1>
      <p :if={@field == "email"}>
        If <strong>{@value}</strong> can use SAR Duty, we've emailed it a 6-digit code. It
        works once, for 15 minutes.
      </p>
      <p :if={@field == "phone"}>
        If <strong>{Service.Phone.format(@value)}</strong> can use SAR Duty, we've texted it a
        6-digit code. It works once, for 15 minutes.
      </p>
      <.form
        for={@form}
        id="login_code_form"
        action={~p"/login"}
        phx-submit="submit"
        phx-trigger-action={@trigger_submit}
      >
        <input type="hidden" name={@form[@field].name} value={@value} />
        <.input
          field={@form[:code]}
          type="text"
          label="Code"
          required
          autocomplete="one-time-code"
          inputmode="numeric"
          maxlength="7"
        />
        <.input
          field={@form[:remember_me]}
          type="checkbox"
          label="Remember me on this computer for 60 days"
        >
          Leave it off on a shared computer. Then closing the browser logs you out.
        </.input>
        <.form_actions>
          <.button
            id="login_code_submit"
            variant={:success}
            disabled={@trigger_submit}
            phx-disable-with="Logging in…"
          >
            {if @trigger_submit, do: "Logging in…", else: "Log in"}
          </.button>
        </.form_actions>
      </.form>
      <%= if @field == "email" do %>
        <p class="text-secondary-1">
          No email after a few minutes? Check your spam folder. Only Owners and Editors on a
          team in D4H get a code, at the email D4H has for them.
        </p>
        <p :if={Web.Layouts.dev_mailbox?()} id="login-dev-mailbox">
          In development the email is in the <.a href="/dev/mailbox" external={true}>local mailbox</.a>.
        </p>
        <p>
          <.a id="login-again" navigate={~p"/login"}>Use a different email</.a>
        </p>
      <% else %>
        <p class="text-secondary-1">
          No text after a few minutes? Only Owners and Editors on a team in D4H get a code,
          at the mobile number D4H has for them. Two people with the same number get a code
          by email instead.
        </p>
        <p :if={not Twilio.delivers?()} id="login-dev-text">
          In development the text message is in the server log, not sent.
        </p>
        <p>
          <.a id="login-again" navigate={~p"/login?with=phone"}>Use a different number</.a>
          or <.a id="login-with-email" navigate={~p"/login"}>get a code by email</.a>
        </p>
      <% end %>
    </div>
    """
  end

  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
