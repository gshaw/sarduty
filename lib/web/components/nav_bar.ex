defmodule Web.Components.NavBar do
  use Web, :function_component

  # The top bar: navy with the amber rule. The brand on the left, section links after it,
  # and a menu or a button on the right. See /styles/draft/navigation.

  attr :size, :atom, values: ~w(wide narrow)a, default: :wide
  slot :links
  slot :inner_block

  def site_bar(assigns) do
    ~H"""
    <header class="site-bar print:hidden">
      <div class={[
        "site-bar-inner px-2 m-auto",
        @size == :wide && "container",
        @size == :narrow && "max-w-md"
      ]}>
        <a href="/" class="brand">SAR <span>Duty</span></a>
        <nav :if={@links != []} class="site-bar-links" aria-label="Main">
          {render_slot(@links)}
        </nav>
        <div :if={@links == []} class="flex-1"></div>
        {render_slot(@inner_block)}
      </div>
    </header>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  def site_bar_menu(assigns) do
    ~H"""
    <details class="site-bar-menu relative" role="menu">
      <summary role="button" aria-label="Open account menu">
        <span class="max-w-40 truncate">{@label}</span>
        <.icon name="hero-chevron-down-micro" class="size-4" />
      </summary>
      <div class="menu" role="menu">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  def menu_divider(assigns) do
    ~H"""
    <hr />
    """
  end
end
