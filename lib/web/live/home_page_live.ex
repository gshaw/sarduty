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
        Welcome to <span class="text-danger-1">SAR Duty</span>
      </h1>
      <p class="lead">
        Helpful tools for search and rescue managers.
      </p>
    </hgroup>
    <%= if @current_team do %>
      <hgroup>
        <h2 class="heading mb-0">
          →
          <.a navigate={~p"/#{@current_team.subdomain}"}><%= @current_team.name %></.a>
        </h2>
      </hgroup>
    <% end %>
    <hr class="my-p" />
    <p class="mt-p">
      <%= if Application.get_env(:sarduty, :dev_routes) do %>
        <.a navigate="/styles">Style Guide</.a>
        ·
        <.a href="/dev/dashboard" external={true}>Dashboard</.a>
        ·
        <.a href="/dev/mailbox" external={true}>Mailbox</.a>
      <% end %>
    </p>
    """
  end
end
