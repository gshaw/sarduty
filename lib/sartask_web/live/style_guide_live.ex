defmodule SartaskWeb.StyleGuideLive do
  use SartaskWeb, :live_view

  import SartaskWeb.WebComponents.A

  def render(assigns) do
    ~H"""
    <section class="mb-8">
      <h1 class="title">
        Style Guide
      </h1>
    </section>

    <section class="mb-8">
      <h2 class="heading font-mono">.a</h2>
      <ul class="mb-4 list-disc list-inside">
        <li>
          <.a navigate="/styles">
            Default Link
          </.a>
        </li>
        <li>
          <.a navigate="/styles" kind={:monochrome}>
            Monochrome
          </.a>
        </li>
        <li>
          <.a
            kind={:custom}
            navigate="/styles"
            class="bg-yellow-400 p-1 font-medium underline hover:no-underline"
          >
            Custom
          </.a>
        </li>
      </ul>
    </section>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
