defmodule Web.WebComponents.AppNavBar do
  use Web, :function_component

  import Web.WebComponents.A
  import Web.WebComponents.Avatar

  attr :current_user, :map, default: nil

  def app_nav_bar(assigns) do
    ~H"""
    <.navbar size={:wide} color={:base_1}>
      <.navbar_mobile_menu color={:base_1}>
        <.a kind={:menu_item} navigate="/">Home</.a>
        <%= if Application.get_env(:sarduty, :dev_routes) do %>
          <.a kind={:menu_item} navigate="/styles">Style Guide</.a>
          <.a kind={:menu_item} href="/dev/dashboard" external={true}>Dashboard</.a>
          <.a kind={:menu_item} href="/dev/mailbox" external={true}>Mailbox</.a>
        <% end %>
        <%= if @current_user == nil do %>
          <.navbar_menu_divider />
          <.a kind={:menu_item} navigate="/login">Log in</.a>
          <.a kind={:menu_item} navigate="/signup">Sign up</.a>
        <% end %>
      </.navbar_mobile_menu>
      <.navbar_links>
        <.a kind={:navbar_title} navigate="/">SAR Duty</.a>
        <.navbar_desktop_links :if={Application.get_env(:sarduty, :dev_routes)}>
          <.a kind={:navbar_item} navigate="/styles">Style Guide</.a>
          <.a kind={:navbar_item} href="/dev/dashboard" external={true}>Dashboard</.a>
          <.a kind={:navbar_item} href="/dev/mailbox" external={true}>Mailbox</.a>
        </.navbar_desktop_links>
      </.navbar_links>
      <%= if @current_user do %>
        <.navbar_user_menu color={:base_2}>
          <:menu_label>
            <.avatar initials={"0" <> (@current_user.id |> Integer.to_string())} />
          </:menu_label>
          <.a kind={:menu_item} navigate="/settings">Settings</.a>
          <.navbar_menu_divider />
          <.a kind={:menu_item} method="delete" href="/logout">Log out</.a>
        </.navbar_user_menu>
      <% else %>
        <.a
          role="button"
          kind={:custom}
          navigate="/login"
          class="hidden md:flex mr-1 btn btn-sm btn-outline"
        >
          Log in
        </.a>
        <.a kind={:custom} role="button" navigate="/signup" class="btn btn-sm btn-primary">
          <span class="whitespace-nowrap">
            Sign up
          </span>
        </.a>
      <% end %>
    </.navbar>
    """
  end

  attr :current_user, :map, default: nil

  def narrow_nav_bar(assigns) do
    ~H"""
    <.navbar size={:narrow} color={:base_2}>
      <.navbar_links>
        <.a kind={:navbar_title} navigate="/">SAR Duty</.a>
      </.navbar_links>
      <%= if @current_user do %>
        <.navbar_user_menu color={:base_2}>
          <:menu_label>
            <.avatar initials={"0" <> (@current_user.id |> Integer.to_string())} />
          </:menu_label>
          <.a kind={:menu_item} navigate="/settings">Settings</.a>
          <.navbar_menu_divider />
          <.a kind={:menu_item} method="delete" href="/logout">Log out</.a>
        </.navbar_user_menu>
      <% end %>
    </.navbar>
    """
  end

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
        <%= render_slot(@inner_block) %>
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
        <%= render_slot(@inner_block) %>
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
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  def navbar_desktop_links(assigns) do
    ~H"""
    <span class="ml-4 border-l border-base-200 hidden md:inline-block">
      <%= render_slot(@inner_block) %>
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
    <hr class="my-2 mx-4 text-base-content border-base-3" />
    """
  end
end
