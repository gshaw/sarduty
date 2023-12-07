defmodule Web.Settings.D4HLive do
  use Web, :live_view_narrow

  import Web.WebComponents.A
  alias App.Accounts.User

  def render(assigns) do
    ~H"""
    <div>
      <p>
        <.a navigate={~p"/settings"}>← Settings</.a>
      </p>
      <h1 class="heading">Change D4H access key</h1>

      <.form for={@form} phx-submit="save">
        <.input field={@form[:d4h_access_key]} label="D4H Access Key" class="font-mono text-sm">
          Encrypted at rest using AES 256 encryption.
        </.input>
        <.form_actions>
          <.button class="btn-success">Save changes</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    user_changeset = User.build_changeset(user)

    socket =
      socket
      |> assign_form(user_changeset)

    {:ok, socket}
  end

  defp sanitize_form_params(form_params) do
    Map.take(form_params, ~w(d4h_access_key))
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end

  def handle_event("save", %{"user" => form_params}, socket) do
    # %{"user" => %{"d4h_access_key" => "abc"}}

    user = socket.assigns.current_user

    case User.update(user, sanitize_form_params(form_params)) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Changes saved.")
         |> redirect(to: ~p"/settings")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}

        # {:error, %Ecto.Changeset{} = changeset} ->
        #   conn
        #   |> put_flash(:error, "Could not save changes")
        #   |> render("show.html", changeset: changeset)
    end

    {:noreply, socket}
  end
end
