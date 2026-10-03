defmodule Web.SettingsLive do
  use Web, :live_view_narrow_layout

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Settings")}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading mb-4">Settings</h1>
      <p id="settings-email">
        Logged in as {@current_user.email}. Your email and your teams come from D4H.
      </p>
      <nav class="space-y-2" aria-label="Sidebar">
        <.navlist_item
          :if={@current_team}
          path={~p"/settings/team"}
          icon="hero-users"
          title="Team settings"
        >
          {@current_team.name}
        </.navlist_item>
        <.navlist_item
          :if={@current_team}
          path={~p"/settings/cards"}
          icon="hero-identification"
          title="ID cards"
        >
          Qualifications on the back
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
        "bg-base-0 hover:bg-base-2 border border-hr hover:border-base-content",
        "px-3 py-2 rounded-md",
        "focus:outline-none focus:ring-2 focus:ring-base-content"
      ]}
    >
      <span class="mr-2">
        <.icon name={@icon} class="h-6 w-6" />
      </span>
      <div>
        <div>{@title}</div>
        <div :if={@inner_block != []} class="truncate text-sm text-secondary-1">
          {render_slot(@inner_block)}
        </div>
      </div>
    </.a>
    """
  end
end
