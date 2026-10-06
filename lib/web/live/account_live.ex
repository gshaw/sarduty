defmodule Web.AccountLive do
  @moduledoc """
  Your own page: who you're logged in as, and each team's settings. Settings live under
  each team, so the URL names the team they change (#153).
  """

  use Web, :live_view_narrow_layout

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Account")}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading mb-4">Account</h1>
      <p id="account-email" class="mb-4">
        Logged in as {@current_user.email}. Your email and your teams come from D4H.
      </p>
      <nav :if={@managed_teams != []} class="space-y-2" aria-label="Team settings">
        <.navlist_item
          :for={team <- @managed_teams}
          id={"account-team-#{team.id}-settings"}
          path={~p"/teams/#{team}/settings"}
          icon="hero-users"
          title={team.name}
        >
          Team settings
        </.navlist_item>
      </nav>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :path, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :inner_block

  def navlist_item(assigns) do
    ~H"""
    <.a
      id={@id}
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
