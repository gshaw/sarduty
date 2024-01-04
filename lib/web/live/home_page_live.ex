defmodule Web.HomePageLive do
  use Web, :live_view_marketing_layout

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Welcome")}
  end

  def render(assigns) do
    ~H"""
    <div class="mb-8">
      <h1 class="title-hero">
        Welcome to
        <span class="text-danger-1">SAR<%= Service.StringHelpers.no_break_space() %>Duty</span>
      </h1>
      <p class="lead">
        Helpful tools for search and rescue managers.
      </p>
    </div>
    <%= if @current_team do %>
      <ul class="heading action-list">
        <li>
          <.a navigate={~p"/#{@current_team.subdomain}"}><%= @current_team.name %></.a>
        </li>
      </ul>
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
