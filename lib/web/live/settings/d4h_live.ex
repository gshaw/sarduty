defmodule Web.Settings.D4HLive do
  use Web, :live_view_narrow

  import Web.WebComponents.A

  alias App.Adapter.D4H
  alias App.Operation.ChangeD4HAccessKey
  alias App.Operation.RemoveD4HAccessKey

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(confirmation_message: nil)
      |> assign(page_title: "D4H Access Key")
      |> assign_form(ChangeD4HAccessKey.build_new_changeset())

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <p>
        <.a navigate={~p"/settings"}>← Settings</.a>
      </p>
      <h1 class="heading">D4H access key</h1>

      <%= if @current_user.d4h_access_key do %>
        <dl>
          <dt>Team</dt>
          <dd><%= @current_user.d4h_team_title %></dd>
          <dt>Region</dt>
          <dd><%= D4H.determine_region(@current_user.d4h_api_host) %></dd>
          <dt>Subdomain</dt>
          <dd class="font-mono"><%= @current_user.d4h_team_subdomain %></dd>
          <dt>API Host</dt>
          <dd class="font-mono"><%= @current_user.d4h_api_host %></dd>
        </dl>

        <p>
          <.button phx-click="verify_access_key" class="btn-success">Verify Key</.button>
          <.button phx-click="delete_access_key" class="btn-danger">Delete Key</.button>
        </p>
        <p :if={@confirmation_message}><%= @confirmation_message %></p>
      <% else %>
        <.form for={@form} phx-submit="save">
          <.input field={@form[:access_key]} label="New D4H Access Key" class="font-mono text-sm">
            Encrypted at rest using AES 256 encryption.
          </.input>
          <.input
            field={@form[:api_host]}
            label="D4H Region"
            type="select"
            options={D4H.regions()}
            prompt="Select a region"
          />
          <.form_actions>
            <.button class="btn-success">Save access key</.button>
          </.form_actions>
        </.form>
      <% end %>
    </div>
    """
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "form"))
  end

  def handle_event("verify_access_key", _, socket) do
    message =
      if user_has_valid_key?(socket.assigns.current_user) do
        "Your D4H access key is valid."
      else
        "Your D4H access key is invalid and should be deleted."
      end

    {:noreply, assign(socket, confirmation_message: message)}
  end

  def handle_event("validate", %{"form" => form_params}, socket) do
    changeset = ChangeD4HAccessKey.validate(form_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"form" => form_params}, socket) do
    case ChangeD4HAccessKey.call(form_params, socket.assigns.current_user) do
      {:ok, _user} ->
        {:noreply, push_navigate(socket, to: ~p"/settings/d4h")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("delete_access_key", _, socket) do
    RemoveD4HAccessKey.call(socket.assigns.current_user)

    {:noreply, push_navigate(socket, to: ~p"/settings/d4h")}
  end

  defp user_has_valid_key?(user) do
    d4h = D4H.build_context(user)

    case D4H.fetch_team(d4h) do
      {:ok, team} -> matching_team?(team, user)
      {:error, _response} -> false
    end
  end

  defp matching_team?(team, user) do
    team.title == user.d4h_team_title && team.subdomain == user.d4h_team_subdomain
  end
end
