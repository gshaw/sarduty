defmodule Web.Settings.D4HLive do
  use Web, :live_view_narrow_layout

  alias App.Adapter.D4H
  alias App.Operation.AddD4HAccessKey
  alias App.Operation.RemoveD4HAccessKey

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "D4H Access Key")
      |> assign(team: socket.assigns.current_user.team)
      |> assign(confirmation_message: nil)
      |> assign_form(AddD4HAccessKey.build_new_changeset())

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <p>
        <.a navigate={~p"/settings"}>← Settings</.a>
      </p>
      <h1 class="heading">D4H access key</h1>
      <p>
        <.a
          target="_blank"
          external={true}
          navigate="https://help.d4h.com/article/377-obtaining-an-api-access-key"
        >
          How to obtain a D4H access key.
        </.a>
      </p>
      <%= if @team do %>
        <dl>
          <dt>Team</dt>
          <dd><%= @team.name %></dd>
          <dt>Subdomain</dt>
          <dd class="font-mono"><%= @team.subdomain %></dd>
          <dt>Region</dt>
          <dd><%= D4H.determine_region(@team.d4h_api_host) %></dd>
          <dt>API Host</dt>
          <dd class="font-mono"><%= @team.d4h_api_host %></dd>
        </dl>

        <p>
          <.button phx-click="verify_access_key" class="btn-success">Verify Key</.button>
          <.button phx-click="delete_access_key" class="btn-danger">Delete Key</.button>
        </p>
        <p :if={@confirmation_message}><%= @confirmation_message %></p>
      <% else %>
        <.form for={@form} phx-submit="save">
          <.input
            field={@form[:api_host]}
            label="D4H Region"
            type="select"
            options={D4H.regions()}
            prompt="Select a region"
          />
          <.input
            type="textarea"
            rows="18"
            field={@form[:access_key]}
            label="D4H Personal Access Token (PAT)"
            class="font-mono text-sm"
          >
            Encrypted at rest using AES 256 encryption.
          </.input>
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
    changeset = AddD4HAccessKey.validate(form_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"form" => form_params}, socket) do
    case AddD4HAccessKey.call(form_params, socket.assigns.current_user) do
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
    d4h = D4H.build_context_from_user(user)

    case D4H.fetch_team(d4h) do
      {:ok, d4h_team} -> matching_team?(d4h_team, user)
      {:error, _response} -> false
    end
  end

  defp matching_team?(d4h_team, user) do
    d4h_team.subdomain == user.team.subdomain
  end
end
