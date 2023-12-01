defmodule SartaskWeb.WebComponents.AppNavBar do
  use SartaskWeb, :function_component

  import SartaskWeb.WebComponents.A
  import SartaskWeb.WebComponents.Avatar

  attr :current_user, :map, default: nil

  def app_nav_bar(assigns) do
    ~H"""
    <.navbar size={:wide} color={:white}>
      <.navbar_mobile_menu>
        <.a kind={:menu_item} navigate="/">Home</.a>
        <.a kind={:menu_item} navigate="/styles">Style Guide</.a>
        <.a kind={:menu_item} href="/dev/dashboard" external={true}>Dashboard</.a>
        <.a kind={:menu_item} href="/dev/mailbox" external={true}>Mailbox</.a>
        <%= if @current_user == nil do %>
          <.navbar_menu_divider />
          <.a kind={:menu_item} navigate="/users/log_in">Log in</.a>
          <.a kind={:menu_item} navigate="/users/register">Sign up for FREE</.a>
        <% end %>
      </.navbar_mobile_menu>
      <.navbar_links>
        <.a kind={:navbar_title} navigate="/">SAR Duty</.a>
        <.navbar_desktop_links>
          <.a kind={:navbar_item} navigate="/styles">Style Guide</.a>
          <.a kind={:navbar_item} href="/dev/dashboard" external={true}>Dashboard</.a>
          <.a kind={:navbar_item} href="/dev/mailbox" external={true}>Mailbox</.a>
        </.navbar_desktop_links>
      </.navbar_links>
      <%= if @current_user do %>
        <.navbar_user_menu current_user={@current_user} color={:white}>
          <:menu_label>
            <.avatar initials={"0" <> (@current_user.id |> Integer.to_string())} />
          </:menu_label>
          <.a kind={:menu_item} navigate="/users/settings">Settings</.a>
          <.navbar_menu_divider />
          <.a kind={:menu_item} method="delete" href="/users/log_out">Log out</.a>
        </.navbar_user_menu>
      <% else %>
        <.a
          role="button"
          kind={:custom}
          navigate="/users/log_in"
          class="hidden md:flex mr-1 btn btn-sm btn-outline"
        >
          Log in
        </.a>
        <.a kind={:custom} role="button" navigate="/users/register" class="btn btn-sm btn-primary">
          <span class="whitespace-nowrap">
            Sign up<span class="hidden lg:inline"> for FREE</span>
          </span>
        </.a>
      <% end %>
    </.navbar>
    """
  end

  slot :inner_block, required: true

  def navbar_mobile_menu(assigns) do
    ~H"""
    <details x-description="Mobile menu" class="md:hidden relative">
      <summary
        role="button"
        aria-label="Open main menu"
        class="
          -ml-2 mr-2 border-r
          focus:outline-none focus:ring-inset focus:ring-2 focus:ring-offset-4
          bg-white text-gray-800 border-gray-200
          focus:ring-gray-800 focus:ring-offset-white
        "
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
        class="
          absolute -left-2 top-12 w-48 h-screen z-20 py-2
          border-t border-r
          bg-white text-gray-800 border-gray-200
        "
      >
        <%= render_slot(@inner_block) %>
      </div>
    </details>
    """
  end

  attr :color, :atom, values: [:white, :gray]
  attr :size, :atom, values: [:wide, :narrow]
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
        <%= render_slot(@inner_block) %>
      </div>
    </nav>
    """
  end

  defp determine_color_classes(color) do
    case color do
      :white ->
        "bg-white text-gray-800 border-gray-200 focus:ring-gray-800 focus:ring-offset-white"

      :gray ->
        "bg-gray-200 text-gray-800 border-gray-200 focus:ring-gray-800 focus:ring-offset-gray-100"
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
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  def navbar_desktop_links(assigns) do
    ~H"""
    <span class="ml-4 border-l border-gray-200 hidden md:inline-block">
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  def navbar_user_menu(assigns) do
    ~H"""
    <details class="relative">
      <summary
        role="button"
        aria-label="Open menu"
        class={[
          "rounded-full focus:outline-none focus:ring-2 focus:ring-offset-2",
          determine_color_classes(@color)
        ]}
      >
        <%= render_slot(@menu_label) %>
      </summary>
      <div
        role="menu"
        class={[
          "absolute -right-2 top-0 mt-10 w-40 py-2 border z-20",
          determine_color_classes(@color)
        ]}
      >
        <%= render_slot(@inner_block) %>
      </div>
    </details>
    """
  end

  def navbar_menu_divider(assigns) do
    ~H"""
    <hr class="my-2 mx-4 bg-white text-gray-800 border-gray-200" />
    """
  end
end
