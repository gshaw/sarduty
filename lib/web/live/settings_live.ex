defmodule Web.SettingsLive do
  use Web, :live_view_narrow

  import Web.WebComponents.A
  alias App.Accounts

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
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading mb-4">Settings</h1>
      <nav class="space-y-2" aria-label="Sidebar">
        <.navlist_item
          path={~p"/settings/email"}
          icon="hero-at-symbol"
          title="Change email"
          subtitle={@current_user.email}
        />
        <.navlist_item path={~p"/settings/password"} icon="hero-key" title="Change password" />
      </nav>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  def navlist_item(assigns) do
    ~H"""
    <.a
      navigate={@path}
      kind={:custom}
      class={[
        "flex items-center",
        "bg-base-0 hover:bg-base-2 border hover:border-base-content",
        "px-3 py-2 rounded-md",
        "focus:outline-none focus:ring-2 focus:ring-base-content"
      ]}
    >
      <span class="mr-2">
        <.icon name={@icon} class="h-6 w-6" />
      </span>
      <div>
        <div><%= @title %></div>
        <div :if={@subtitle} class="truncate text-sm text-secondary-0">
          <%= @subtitle %>
        </div>
      </div>
    </.a>
    """
  end
end
