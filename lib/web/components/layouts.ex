defmodule Web.Layouts do
  use Web, :html
  import Web.WebComponents.A
  import Web.WebComponents.Avatar

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="[scrollbar-gutter:stable]" data-theme="tailwind">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title suffix=" · SAR Duty">
          <%= assigns[:page_title] || "Untitled Page" %>
        </.live_title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
        </script>
      </head>
      <body class="bg-base-1 text-base-content">
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def marketing(assigns) do
    ~H"""
    <.marketing_nav_bar current_user={@current_user} />
    <main role="main" class="lg:container mx-auto pt-16 px-2 mb-p2">
      <div class="mx-auto max-w-2xl">
        <.flash_group flash={@flash} />
        <%= @inner_content %>
      </div>
    </main>
    """
  end

  def app(assigns) do
    ~H"""
    <.app_nav_bar current_user={@current_user} />
    <main role="main" class="lg:container mx-auto pt-16 px-2 mb-p2">
      <div class="mx-auto max-w-2xl">
        <.flash_group flash={@flash} />
        <%= @inner_content %>
      </div>
    </main>
    """
  end

  def narrow(assigns) do
    ~H"""
    <.narrow_nav_bar current_user={@current_user} />
    <main role="main" class="max-w-narrow m-auto px-2 pt-16 mb-p2">
      <div class="mx-auto max-w-2xl">
        <.flash_group flash={@flash} />
        <%= @inner_content %>
      </div>
    </main>
    """
  end

  attr :current_user, :map, default: nil

  defp narrow_nav_bar(assigns) do
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

  attr :current_user, :map, default: nil

  def app_nav_bar(assigns) do
    ~H"""
    <.navbar size={:wide} color={:base_1}>
      <.navbar_mobile_menu color={:base_1}>
        <.a kind={:menu_item} navigate="/">SAR Duty</.a>
      </.navbar_mobile_menu>
      <.navbar_links>
        <.a kind={:navbar_title} navigate="/">SAR Duty</.a>
      </.navbar_links>
      <.current_user_menu current_user={@current_user} />
    </.navbar>
    """
  end

  attr :current_user, :map, default: nil

  defp current_user_menu(assigns) do
    ~H"""
    <.navbar_user_menu color={:base_2}>
      <:menu_label>
        <.avatar initials={"0" <> (@current_user.id |> Integer.to_string())} />
      </:menu_label>
      <.a kind={:menu_item} navigate="/settings">Settings</.a>
      <.navbar_menu_divider />
      <.a kind={:menu_item} method="delete" href="/logout">Log out</.a>
    </.navbar_user_menu>
    """
  end

  attr :current_user, :map, default: nil

  def marketing_nav_bar(assigns) do
    ~H"""
    <.navbar size={:wide} color={:base_1}>
      <.navbar_mobile_menu color={:base_1}>
        <.a kind={:menu_item} navigate="/">SAR Duty</.a>
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
        <.current_user_menu current_user={@current_user} />
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
end
