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
        <meta name="theme-color" content={theme_color(@conn)} />
        <.live_title suffix=" · SAR Duty">
          {assigns[:page_title] || "Untitled Page"}
        </.live_title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script phx-track-static type="module" src={~p"/assets/js/app.js"}>
        </script>
      </head>
      <body class="bg-base-1 text-base-content">
        {@inner_content}
      </body>
    </html>
    """
  end

  # Safari tints the status bar with theme-color, so it matches the bar at the top:
  # zinc-100 (bg-base-2) for the app's navbar, slate-800 for the verify site's.
  defp theme_color(%Plug.Conn{host: host}) do
    if host == Web.VerifyHost.host(), do: "#1e293b", else: "#f4f4f5"
  end

  def marketing(assigns) do
    ~H"""
    <.marketing_nav_bar current_user={@current_user} />
    <main role="main" class="container mx-auto pt-16 px-2 mb-p2">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    <.site_footer current_user={@current_user} />
    """
  end

  def app(assigns) do
    ~H"""
    <.app_nav_bar current_user={@current_user} />
    <main role="main" class="container mx-auto pt-16 px-2 mb-p2">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    <.site_footer current_user={@current_user} />
    """
  end

  # The verify site: a navy bar with the host beside it, so it doesn't look like the app,
  # and the host is what a checker is told to look for. No app navigation, no login. The
  # footer credits SAR Duty quietly, and stays when the bar carries an organization's brand.
  def verify(assigns) do
    ~H"""
    <header class="sticky top-0 z-30 bg-slate-800 text-white">
      <div class="max-w-md mx-auto px-4 h-12 flex items-center justify-between">
        <a href="/" class="font-semibold">SAR <span class="text-amber-400">Duty</span></a>
        <span id="verify-host" class="text-sm text-slate-300">{Web.VerifyHost.host()}</span>
      </div>
    </header>
    <main role="main" class="max-w-md mx-auto px-4 pt-6 pb-8">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    <footer id="verify-footer" class="max-w-md mx-auto px-4 pb-8 text-center text-xs text-zinc-400">
      Powered by <a href={Web.Endpoint.url()} class="hover:underline">{Web.Endpoint.host()}</a>
    </footer>
    """
  end

  def narrow(assigns) do
    ~H"""
    <.narrow_nav_bar current_user={@current_user} />
    <main role="main" class="max-w-md m-auto px-2 pt-16 mb-p2">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    <.site_footer current_user={@current_user} />
    """
  end

  attr :current_user, :map, default: nil

  # The main site's footer. The verify site is a separate host, so its link is a full URL.
  defp site_footer(assigns) do
    assigns =
      assign(assigns,
        admin?: assigns.current_user && assigns.current_user.is_admin,
        dev_routes?: Application.get_env(:sarduty, :dev_routes),
        mailbox?: Application.get_env(:swoosh, :local)
      )

    ~H"""
    <footer id="site-footer" class="container mx-auto px-2 mb-p2">
      <p class="pt-p border-t border-hr">
        <.a id="footer-verify" href={Web.VerifyHost.url()}>Verify an ID card</.a>
        <%= if @admin? do %>
          ·
          <.a id="footer-styles" navigate="/styles">Style Guide</.a>
          ·
          <.a href="https://github.com/gshaw/sarduty" external={true}>GitHub</.a>
          ·
          <.a navigate="/admin">Admin</.a>
        <% end %>
        <%= if @dev_routes? do %>
          ·
          <.a href="/dev/dashboard" external={true}>Dashboard</.a>
          <%= if @mailbox? do %>
            ·
            <.a href="/dev/mailbox" external={true}>Mailbox</.a>
          <% end %>
        <% end %>
      </p>
    </footer>
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
        <.button navigate="/login" size={:sm} class="mr-1">Log in</.button>
        <%!-- <.button navigate="/signup" size={:sm} variant={:primary}>Sign up</.button> --%>
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
