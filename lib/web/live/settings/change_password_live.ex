defmodule Web.Settings.ChangePasswordLive do
  use Web, :live_view_narrow

  import Web.WebComponents.A
  alias App.Accounts

  def render(assigns) do
    ~H"""
    <div>
      <p>
        <.a navigate={~p"/settings"}>← Settings</.a>
      </p>
      <h1 class="heading">Change password</h1>

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/login?_action=password_updated"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <.input
          field={@password_form[:current_password]}
          name="current_password"
          type="password"
          label="Current password"
          id="current_password_for_password"
          value={@current_password}
          required
        >
          Required to protect your account before sensitive actions.<br />
          <.a navigate={~p"/login/reset?back=change_password"} class="link">
            Forgot your password?
          </.a>
        </.input>
        <.input
          field={@password_form[:email]}
          type="hidden"
          id="hidden_user_email"
          value={@current_email}
        />
        <.input field={@password_form[:password]} type="password" label="New password" required />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
        />

        <.form_actions>
          <.button class="btn-success">Change password</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok ->
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)

    socket =
      socket
      |> assign(:page_title, "Change Password")
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end
end
