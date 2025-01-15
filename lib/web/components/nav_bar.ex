defmodule Web.Components.NavBar do
  use Web, :function_component

  attr :color, :atom, required: true
  slot :inner_block, required: true

  def navbar_mobile_menu(assigns) do
    ~H"""
    <details x-description="Mobile menu" role="menu" class="md:hidden relative">
      <summary
        role="button"
        aria-label="Open main menu"
        class={[
          "-ml-2 mr-2 border-r",
          "focus:outline-none focus:ring-inset focus:ring-2 focus:ring-offset-4",
          determine_color_classes(@color)
        ]}
      >
        <div
          x-description="Mobile menu opened and closed icons"
          aria-hidden="true"
          class="h-12 w-12 flex items-center justify-center"
        >
          <span class="display-when-details-closed">
            <.icon name="hero-bars-3" class="h-6 w-6" />
          </span>
          <span class="display-when-details-opened">
            <.icon name="hero-x-mark" class="h-6 w-6" />
          </span>
        </div>
      </summary>
      <div
        x-description="Mobile menu"
        role="menu"
        class={[
          "absolute -left-2 top-12 w-48 h-screen z-20 py-2",
          "border-t border-r",
          determine_color_classes(:base_2)
        ]}
      >
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  attr :color, :atom, values: ~w(base_1 base_2)a
  attr :size, :atom, values: ~w(wide narrow)a
  slot :inner_block, required: true

  def navbar(assigns) do
    ~H"""
    <nav
      x-description="Navbar element"
      class={[
        "border-b fixed w-full z-30 print:hidden",
        determine_color_classes(@color)
      ]}
    >
      <div class={[
        "px-2 m-auto h-12 flex items-center",
        determine_container_classes(@size)
      ]}>
        {render_slot(@inner_block)}
      </div>
    </nav>
    """
  end

  defp determine_color_classes(color) do
    case color do
      :base_1 ->
        "bg-base-1 text-base-content border-base-2 focus:ring-base-content focus:ring-offset-base-1"

      :base_2 ->
        "bg-base-2 text-base-content border-base-3 focus:ring-base-content focus:ring-offset-base-2"
    end
  end

  defp determine_container_classes(size) do
    case size do
      :wide -> "lg:container"
      :narrow -> "max-w-narrow"
    end
  end

  slot :inner_block, required: true

  def navbar_links(assigns) do
    ~H"""
    <div class="flex-grow">
      <div class="flex align-items">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  def navbar_desktop_links(assigns) do
    ~H"""
    <span class="ml-4 border-l border-base-200 hidden md:inline-block">
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :color, :atom, required: true
  slot :menu_label, required: true
  slot :inner_block, required: true

  def navbar_user_menu(assigns) do
    ~H"""
    <details class="relative" role="menu">
      <summary
        role="button"
        aria-label="Open menu"
        class={[
          "rounded-full focus:outline-none focus:ring-2 focus:ring-offset-2",
          determine_color_classes(@color)
        ]}
      >
        {render_slot(@menu_label)}
      </summary>
      <div
        role="menu"
        class={[
          "absolute -right-2 top-0 mt-10 w-40 py-2 border z-20",
          determine_color_classes(@color)
        ]}
      >
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  def navbar_menu_divider(assigns) do
    ~H"""
    <hr class="my-2 mx-4 text-base-content border-base-3" />
    """
  end
end
