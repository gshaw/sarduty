defmodule SartaskWeb.HomePageLive do
  use SartaskWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Welcome")}
  end

  def render(assigns) do
    ~H"""
    <section>
      <h1 class="title">
        Welcome to <span class="text-brand">SAR Duty</span>
      </h1>
      <div class="lead">
        Helpful tools for search and rescue managers.
      </div>
    </section>
    """
  end
end
