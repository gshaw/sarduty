defmodule Web.TeamDashboardLive do
  use Web, :live_view_app

  import Web.WebComponents.A

  alias App.Adapter.D4H

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title-hero mb-p"><%= @current_team.title %></h1>

    <div class="mb-p">
      <h2 class="heading">
        → <.a
          external={true}
          external_icon_class="w-8 h-8 ml-2 mb-2"
          href={D4H.build_url(@current_team, "/dashboard")}
          phx-no-format
        >Open D4H Dashboard</.a>
      </h2>

      <h2 class="heading">
        →
        <.a navigate={~p"/#{@current_team.subdomain}/activities"}>Activities</.a>
      </h2>
    </div>
    """
  end
end
