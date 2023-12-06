defmodule Web.HomePageLive do
  use Web, :live_view_marketing

  import Web.WebComponents.A

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Welcome")}
  end

  def render(assigns) do
    ~H"""
    <hgroup class="mb-8">
      <h1 class="title-hero">
        Welcome to <span class="text-primary-1">SAR Duty</span>
      </h1>
      <p class="lead">
        Helpful tools for search and rescue managers.
      </p>
    </hgroup>
    <%= if @current_user do %>
      <hgroup>
        <h2 class="heading mb-0">
          →
          <.a navigate={~p"/southfrasersar"}>South Fraser SAR</.a>
        </h2>
      </hgroup>
    <% end %>
    """
  end
end
