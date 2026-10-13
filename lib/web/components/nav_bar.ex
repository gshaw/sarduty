defmodule Web.Components.NavBar do
  use Web, :function_component

  # The top bar: navy with the amber rule. The brand on the left, the area's name after it,
  # and a menu or a button on the right. See /styles/top-bar.

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
        <span class="truncate">{@label}</span>
        <.icon name="hero-chevron-down-micro" />
      </summary>
      <div class="menu" role="menu">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  slot :inner_block, required: true

  # Below 1024px the bar's links and account menu move behind this button. The panel opens
  # under the bar, and live navigation renders the page again, which closes it.
  def site_bar_phone_menu(assigns) do
    ~H"""
    <details id="phone-menu" class="site-bar-phone group">
      <summary id="phone-menu-button" aria-label="Menu">
        <.icon name="hero-bars-3" class="group-open:hidden" />
        <.icon name="hero-x-mark" class="hidden group-open:inline-block" />
        <span>Menu</span>
      </summary>
      <nav class="site-bar-phone-panel" aria-label="Main">
        {render_slot(@inner_block)}
      </nav>
    </details>
    """
  end

  attr :label, :string, required: true, doc: "the area, as the nav's aria-label"

  slot :group, required: true do
    attr :heading, :string, doc: "nil for a group of one link"
  end

  # An area's pages down the left of each of its pages (#312), in groups with a heading
  # over each group of two or more. Below 1024px the Menu button holds them instead. See
  # /styles/side-nav.
  def side_nav(assigns) do
    ~H"""
    <nav id="side-nav" class="side-nav" aria-label={@label}>
      <div :for={group <- @group} class="side-nav-group">
        <div :if={group[:heading]} class="caps side-nav-heading">{group.heading}</div>
        {render_slot(group)}
      </div>
    </nav>
    """
  end

  def menu_divider(assigns) do
    ~H"""
    <hr />
    """
  end
end
