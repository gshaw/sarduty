defmodule SartaskWeb.HomePageLive do
  use SartaskWeb, :live_view

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

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
