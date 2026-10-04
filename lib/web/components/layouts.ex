defmodule Web.Layouts do
  use Web, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="[scrollbar-gutter:stable]">
      <head>
        <meta charset="utf-8" />
        <meta name="description" content="Helpful tools for search and rescue managers." />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <meta name="theme-color" content="#13243a" media="(prefers-color-scheme: light)" />
        <meta name="theme-color" content="#0a111b" media="(prefers-color-scheme: dark)" />
        <.live_title suffix=" · SAR Duty">
          {assigns[:page_title] || "Untitled page"}
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
  # footer credits SAR Duty quietly. An organization's scan page puts its brand in the bar
  # and its name in the footer, and leaves the check itself alone: it works for any card.
  def verify(assigns) do
    assigns = assign(assigns, :organization, assigns[:organization])

    ~H"""
    <header class="verify-bar sticky top-0 z-30">
      <div class="max-w-md mx-auto px-4 h-12 flex items-center justify-between gap-4">
        <a :if={@organization == nil} href="/" class="brand">SAR <span>Duty</span></a>
        <a
          :if={@organization}
          id="verify-organization"
          href={~p"/o/#{@organization.slug}"}
          class="flex items-center gap-2 font-semibold"
        >
          <img
            :if={@organization.logo}
            src={Web.OrganizationController.logo_url(@organization)}
            alt=""
            class="size-8 shrink-0"
          />
          {@organization.short_name}
        </a>
        <span id="verify-host" class="verify-host">{Web.VerifyHost.host()}</span>
      </div>
    </header>
    <main role="main" class="max-w-md mx-auto px-4 pt-6 pb-8">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    <footer id="verify-footer" class="max-w-md mx-auto px-4 pb-8 text-center text-xs text-secondary-1">
      <span :if={@organization} id="verify-footer-organization">
        <a :if={@organization.website} href={@organization.website} class="hover:underline">
          {@organization.name}
        </a>
        <span :if={!@organization.website}>{@organization.name}</span>
        ·
      </span>
      Powered by <a href={Web.Endpoint.url()} class="hover:underline">{Web.Endpoint.host()}</a>
    </footer>
    """
  end

  # Login and settings forms: one task on the page, so no footer links to wander off to.
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
          <.a id="footer-styles" navigate="/styles">Style guide</.a>
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
    <.site_bar size={:narrow}>
      <.account_menu :if={@current_user} current_user={@current_user} />
    </.site_bar>
    """
  end

  attr :current_user, :map, default: nil

  def app_nav_bar(assigns) do
    ~H"""
    <.site_bar>
      <.account_menu current_user={@current_user} />
    </.site_bar>
    """
  end

  attr :current_user, :map, default: nil

  defp account_menu(assigns) do
    ~H"""
    <.site_bar_menu label={@current_user.email}>
      <.a kind={:custom} navigate="/settings">Settings</.a>
      <.menu_divider />
      <.a kind={:custom} method="delete" href="/logout">Log out</.a>
    </.site_bar_menu>
    """
  end

  attr :current_user, :map, default: nil

  def marketing_nav_bar(assigns) do
    ~H"""
    <.site_bar>
      <%= if @current_user do %>
        <.account_menu current_user={@current_user} />
      <% else %>
        <.button navigate="/login" size={:sm}>Log in</.button>
      <% end %>
    </.site_bar>
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
    <div id={@id} class="toasts">
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
        Reconnecting… <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="The page stopped responding"
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        Reconnecting… <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end
end
