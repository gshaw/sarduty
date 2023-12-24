defmodule Web.SettingsLive do
  use Web, :live_view_narrow_layout

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
    {:ok, assign(socket, page_title: "Settings")}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading mb-4">Settings</h1>
      <nav class="space-y-2" aria-label="Sidebar">
        <.navlist_item path={~p"/settings/email"} icon="hero-at-symbol" title="Change email">
          <%= @current_user.email %>
        </.navlist_item>
        <.navlist_item path={~p"/settings/password"} icon="hero-lock-closed" title="Change password" />
        <.navlist_item path={~p"/settings/d4h"} icon="hero-key" title="D4H access key">
          <div :if={@current_user.team} class="font-mono">
            <%= @current_user.team.subdomain %>
          </div>
        </.navlist_item>
        <.navlist_item
          :if={@current_team}
          path={~p"/settings/team"}
          icon="hero-users"
          title="Team settings"
        >
          <%= if @current_user.team, do: @current_user.team.name %>
        </.navlist_item>
      </nav>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :inner_block

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
        <div :if={@inner_block} class="truncate text-sm text-secondary-1">
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </.a>
    """
  end
end
