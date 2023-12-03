defmodule Web.HomePageLive do
  use Web, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Welcome")}
  end

  def render(assigns) do
    ~H"""
    <hgroup>
      <h1 class="title">
        Welcome to <span class="text-primary-1">SAR Duty</span>
      </h1>
      <p class="lead">
        Helpful tools for search and rescue managers.
      </p>
    </hgroup>
    """
  end
end
