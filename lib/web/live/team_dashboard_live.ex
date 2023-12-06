defmodule Web.TeamDashboardLive do
  use Web, :live_view_app

  import Web.WebComponents.A

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title-hero mb-p">South Fraser SAR</h1>
    <h2 class="heading">
      →
      <.a navigate={~p"/southfrasersar/activities"}>Activities</.a>
    </h2>
    """
  end
end
