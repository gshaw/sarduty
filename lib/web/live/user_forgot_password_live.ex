defmodule Web.UserForgotPasswordLive do
  use Web, :live_view_narrow

  alias App.Accounts

  def render(assigns) do
    ~H"""
    <div>
      <p :if={@current_user == nil}>
        <.a navigate={~p"/login"} class="link">← Log in</.a>
      </p>
      <h1 class="heading">Forgot your password?</h1>
      <p>
        Hey, it happens to everyone. Enter the email address you use to log in with and we'll send a link with instructions.
      </p>

      <.form for={@form} id="reset_password_form" phx-submit="send_email">
        <.input field={@form[:email]} type="email" label="Email" required />
        <.form_actions>
          <.button class="btn-success">Send password reset link</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Forgot password",
        form: to_form(%{}, as: "user")
      )

    {:ok, socket}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/login/reset/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
