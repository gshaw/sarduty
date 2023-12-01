defmodule SartaskWeb.StyleGuideLive do
  use SartaskWeb, :live_view

  import SartaskWeb.WebComponents.A

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Style Guide")}
  end

  def render(assigns) do
    ~H"""
    <section class="mb-8">
      <h1 class="title">
        Style Guide
      </h1>
    </section>

    <.style_group title=".a">
      <div class="flex space-x-4">
        <.a navigate="/styles">Default Link</.a>
        <.a navigate="/styles" kind={:monochrome}>Monochrome</.a>
        <.a kind={:custom} navigate="/styles" class="underline hover:no-underline">
          Custom
        </.a>
      </div>
    </.style_group>

    <.style_group title=".btn">
      <div class="flex flex-wrap">
        <div class="flex-grow">
          <button class="btn btn-success">Save</button>
          <button class="btn btn-success">Save and Close</button>
          <button class="btn">Cancel</button>
          <button class="btn btn-link">More Information</button>
        </div>
        <button class="btn btn-error">Delete</button>
      </div>
      <div class="pt-8">
        <p>Examples of all button styles but the app mainly uses the default, success, and error.</p>
        <button class="btn">Button</button>
        <button class="btn btn-neutral">Neutral</button>
        <button class="btn btn-primary">Primary</button>
        <button class="btn btn-secondary">Secondary</button>
        <button class="btn btn-accent">Accent</button>
        <button class="btn btn-ghost">Ghost</button>
        <button class="btn btn-link">Link</button>
      </div>
      <div>
        <button class="btn btn-info">Info</button>
        <button class="btn btn-success">Success</button>
        <button class="btn btn-warning">Warning</button>
        <button class="btn btn-error">Error</button>
      </div>
      <div>
        <button class="btn btn-lg">Large</button>
        <button class="btn">Normal</button>
        <button class="btn btn-sm">Small</button>
        <button class="btn btn-xs">Tiny</button>
      </div>
      <div class="div">
        <a class="btn btn-sm btn-outline btn-secondary">Log in</a>
        <a class="btn btn-sm btn-primary">Sign up for FREE</a>
      </div>
    </.style_group>

    <.style_group title=".badge">
      <div class="badge">default</div>
      <div class="badge badge-primary">primary</div>
      <div class="badge badge-secondary">secondary</div>
      <div class="badge badge-accent">accent</div>
      <div class="badge badge-success">success</div>
      <div class="badge badge-warning">warning</div>
      <div class="badge badge-error">error</div>
    </.style_group>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def style_group(assigns) do
    ~H"""
    <section class="bg-gray-50 p-4 space-y-4 mb-8 rounded">
      <h2 class="heading font-mono"><%= @title %></h2>
      <%= render_slot(@inner_block) %>
    </section>
    """
  end
end
