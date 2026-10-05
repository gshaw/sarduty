defmodule Web.UserLoginCodeLive do
  use Web, :live_view_narrow_layout

  # Shown after asking for a code. The email comes from the session, so a refresh keeps
  # this page; sign-up links here with it in the query instead. Like the email form, the
  # submit goes through LiveView, then posts to the controller, which logs in. The button
  # stays busy until that POST leaves the page.
  def mount(params, session, socket) do
    case session["login_email"] || params["email"] do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/login")}

      email ->
        form =
          to_form(%{"email" => email, "code" => nil, "remember_me" => "false"}, as: "user")

        {:ok,
         assign(socket,
           page_title: "Enter your code",
           email: email,
           form: form,
           trigger_submit: false
         )}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="login-code">
      <h1 class="heading">Enter your code</h1>
      <p>
        If <strong>{@email}</strong> can use SAR Duty, we've emailed it a 6-digit code. It
        works once, for 15 minutes.
      </p>
      <.form
        for={@form}
        id="login_code_form"
        action={~p"/login"}
        phx-submit="submit"
        phx-trigger-action={@trigger_submit}
      >
        <input type="hidden" name={@form[:email].name} value={@email} />
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
    </div>
    """
  end

  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
