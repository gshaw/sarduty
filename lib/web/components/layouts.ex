defmodule Web.Layouts do
  use Web, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="[scrollbar-gutter:stable]" data-theme="tailwind">
      <head>
        <meta charset="utf-8" />
        <meta name="description" content="Helpful tools for search and rescue managers." />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title suffix=" · SAR Duty">
          {assigns[:page_title] || "Untitled Page"}
        </.live_title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
        </script>
      </head>
      <body class="bg-base-1 text-base-content">
        {@inner_content}
      </body>
    </html>
    """
  end

  def marketing(assigns) do
    ~H"""
    <.marketing_nav_bar current_user={@current_user} />
    <main role="main" class="container mx-auto pt-16 px-2 mb-p2">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    """
  end

  def app(assigns) do
    ~H"""
    <.app_nav_bar current_user={@current_user} />
    <main role="main" class="container mx-auto pt-16 px-2 mb-p2">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    """
  end

  def narrow(assigns) do
    ~H"""
    <.narrow_nav_bar current_user={@current_user} />
    <main role="main" class="max-w-md m-auto px-2 pt-16 mb-p2">
      <.flash_group flash={@flash} />
      {@inner_content}
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
    <.navbar size={:wide} color={:base_2}>
      <%!-- <.navbar_mobile_menu color={:base_1}>
        <.a kind={:menu_item} navigate="/">SAR Duty</.a>
      </.navbar_mobile_menu> --%>
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
    <.navbar size={:wide} color={:base_2}>
      <%!-- <.navbar_mobile_menu color={:base_1}>
        <.a kind={:menu_item} navigate="/">SAR Duty</.a>
        <%= if @current_user == nil do %>
          <.navbar_menu_divider />
          <.a kind={:menu_item} navigate="/login">Log in</.a>
          <.a kind={:menu_item} navigate="/signup">Sign up</.a>
        <% end %>
      </.navbar_mobile_menu> --%>
      <.navbar_links>
        <.a kind={:navbar_title} navigate="/">SAR Duty</.a>
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
        <%!--
        <.a kind={:custom} role="button" navigate="/signup" class="btn btn-sm btn-primary">
          <span class="whitespace-nowrap">
            Sign up
          </span>
        </.a>
        --%>
      <% end %>
    </.navbar>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} title="Error" flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title="Server disconnected"
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        Attempting to reconnect <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        Hang in there while we get back on track
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end
end
