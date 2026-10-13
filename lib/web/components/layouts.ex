defmodule Web.Layouts do
  use Web, :html

  alias Web.Navigation

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="description" content="Less paperwork for search and rescue teams that use D4H." />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <meta name="theme-color" content="#13243a" media="(prefers-color-scheme: light)" />
        <meta name="theme-color" content="#0a111b" media="(prefers-color-scheme: dark)" />
        <.live_title suffix=" · SAR Duty">
          {assigns[:page_title] || "Untitled page"}
        </.live_title>
        <.favicon_links />
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script phx-track-static type="module" src={~p"/assets/js/app.js"}>
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  # Public pages run edge to edge under the bar, so the home page's bands can; a page sets
  # its own width.
  def marketing(assigns) do
    ~H"""
    <.main_nav_bar {nav_assigns(assigns)} />
    <main role="main" class="under-site-bar mb-8">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    <.site_footer current_user={@current_user} />
    """
  end

  @doc "The SD favicon and the home screen icon. See /styles/logo."
  def favicon_links(assigns) do
    ~H"""
    <link rel="icon" href="/favicon.ico" sizes="48x48" />
    <link rel="icon" href={~p"/images/sarduty-favicon.svg"} type="image/svg+xml" />
    <link rel="apple-touch-icon" href={~p"/images/apple-touch-icon.png"} />
    """
  end

  # Team, member, and admin pages put their area's pages down the left. Your settings has
  # one page, so no side navigation.
  def app(assigns) do
    {area, groups} = assigns |> nav_assigns() |> navigation()
    assigns = assign(assigns, nav_area: area, nav_groups: groups)

    ~H"""
    <.main_nav_bar {nav_assigns(assigns)} />
    <%= if @nav_groups != [] do %>
      <div class="with-side-nav container mx-auto pt-16 px-2 mb-8">
        <.area_side_nav area={@nav_area} groups={@nav_groups} />
        <main role="main" class="side-nav-main">
          <.flash_group flash={@flash} />
          {@inner_content}
        </main>
      </div>
    <% else %>
      <main role="main" class="container mx-auto pt-16 px-2 mb-8">
        <.flash_group flash={@flash} />
        {@inner_content}
      </main>
    <% end %>
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
          href={~p"/orgs/#{@organization}"}
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
    <footer id="verify-footer" class="max-w-md mx-auto px-4 pb-8 text-center text-xs text-text-muted">
      <span :if={@organization} id="verify-footer-organization">
        <a :if={@organization.website} href={@organization.website} class="hover:underline">
          {@organization.name}
        </a>
        <span :if={!@organization.website}>{@organization.name}</span>
        ·
      </span>
      Powered by <a href={Web.Endpoint.url()} class="hover:underline">{Web.Endpoint.host()}</a>
      ·
      <a id="verify-footer-privacy" href={Web.Endpoint.url() <> "/privacy"} class="hover:underline">
        Privacy
      </a>
      ·
      <a id="verify-footer-terms" href={Web.Endpoint.url() <> "/terms"} class="hover:underline">
        Terms
      </a>
    </footer>
    """
  end

  # Login and settings forms: one task on the page, so no footer links to wander off to.
  def narrow(assigns) do
    ~H"""
    <.main_nav_bar {nav_assigns(assigns)} size={:narrow} />
    <main role="main" class="max-w-md m-auto px-2 pt-16 mb-8">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    <.dev_footer />
    """
  end

  # Login and settings pages have no footer, but in dev the mailbox is where login codes go.
  defp dev_footer(assigns) do
    assigns = assign(assigns, mailbox?: dev_mailbox?())

    ~H"""
    <footer :if={@mailbox?} id="dev-footer" class="max-w-md m-auto px-2 mb-8 text-sm">
      <p class="pt-4 border-t border-border-subtle">
        Development:
        <.a href="/dev/mailbox" external={true}>Mailbox</.a>
      </p>
    </footer>
    """
  end

  @doc "Whether mail goes to the local mailbox at /dev/mailbox, as in development."
  def dev_mailbox? do
    Application.get_env(:sarduty, :dev_routes) == true and
      Application.get_env(:swoosh, :local) == true
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
    <footer id="site-footer" class="container mx-auto px-2 mb-8">
      <p class="pt-4 border-t border-border-subtle">
        <.a id="footer-verify" href={Web.VerifyHost.url()}>Verify an ID card</.a>
        ·
        <.a id="footer-terms" navigate={~p"/terms"}>Terms</.a>
        ·
        <.a id="footer-privacy" navigate={~p"/privacy"}>Privacy</.a>
        <%= if @admin? do %>
          ·
          <.a id="footer-styles" href="/styles">Style guide</.a>
          ·
          <.a href="https://github.com/gshaw/sarduty" external={true}>GitHub</.a>
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

  # What the top bar and the side navigation need from a page's assigns. Pages that don't
  # load a user have none.
  defp nav_assigns(assigns) do
    %{
      current_user: assigns[:current_user],
      current_team: assigns[:current_team],
      member: assigns[:member],
      managed_teams: assigns[:managed_teams] || [],
      member_logins: assigns[:member_logins] || [],
      current_path: assigns[:current_path],
      proposed_change_count: assigns[:proposed_change_count] || 0
    }
  end

  # The page's area and the area's pages, for the bar, the side navigation, and the
  # phone menu. Web.Navigation decides both.
  defp navigation(assigns) do
    area = Navigation.area(assigns.current_path, assigns.current_team, assigns.member)
    {area, Navigation.groups(area, assigns.current_path, assigns.proposed_change_count)}
  end

  attr :current_user, :map, default: nil
  attr :current_team, :map, default: nil
  attr :member, :map, default: nil
  attr :managed_teams, :list, default: []
  attr :member_logins, :list, default: []
  attr :current_path, :string, default: nil
  attr :proposed_change_count, :integer, default: 0
  attr :size, :atom, default: :wide

  # The top bar: the area you're in, then the account menu, which switches areas, or Log
  # in. On a phone the Menu button holds the area's pages and the account menu. See
  # /styles/top-bar.
  def main_nav_bar(assigns) do
    {area, groups} = navigation(assigns)
    assigns = assign(assigns, area: area, groups: groups)

    ~H"""
    <.site_bar size={@size}>
      <:links :if={@area}>
        <.link navigate={@area.home} id="nav-area" class="site-bar-area">
          {@area.name}
          <span :if={@area.kind_label} class="site-bar-area-kind">{@area.kind_label}</span>
        </.link>
      </:links>
      <%= if @current_user do %>
        <.link :if={@area} navigate={@area.home} id="phone-nav-area" class="site-bar-area-phone">
          <span class="site-bar-area-name">{@area.name}</span>
          <span :if={@area.kind_label} class="site-bar-area-kind">{@area.kind_label}</span>
        </.link>
        <.site_bar_menu label={@current_user.email}>
          <.area_links
            current_user={@current_user}
            managed_teams={@managed_teams}
            member_logins={@member_logins}
            area={@area}
          />
        </.site_bar_menu>
        <.site_bar_phone_menu>
          <%= for {heading, links} <- @groups do %>
            <div :if={heading} class="caps menu-heading">{heading}</div>
            <.nav_link :for={link <- links} link={link} id_prefix="phone-nav-" />
          <% end %>
          <.menu_divider :if={@groups != []} />
          <.area_links
            current_user={@current_user}
            managed_teams={@managed_teams}
            member_logins={@member_logins}
            area={@area}
            id_prefix="phone-"
            email
          />
        </.site_bar_phone_menu>
      <% else %>
        <.a id="nav-login" kind={:custom} navigate={~p"/login"} class="site-bar-login">
          <.icon name="hero-arrow-right-end-on-rectangle" /> Log in
        </.a>
      <% end %>
    </.site_bar>
    """
  end

  attr :area, :map, required: true, doc: "from Web.Navigation.area/3"
  attr :groups, :list, required: true, doc: "from Web.Navigation.groups/3"

  @doc "The area's pages down the left, as the app layout shows them. See /styles/side-nav."
  def area_side_nav(assigns) do
    ~H"""
    <.side_nav label={@area.kind_label || @area.name}>
      <:group :for={{heading, links} <- @groups} heading={heading}>
        <.nav_link :for={link <- links} link={link} id_prefix="side-nav-" />
      </:group>
    </.side_nav>
    """
  end

  attr :link, :map, required: true
  attr :id_prefix, :string, required: true

  # One page in the side navigation or the phone menu, with a count when something waits
  # there.
  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@link.path}
      id={@id_prefix <> @link.key}
      aria-current={@link.current && "page"}
      class="nav-link"
    >
      {@link.label}
      <.badge :if={@link.count} kind={:warning}>{@link.count}</.badge>
    </.link>
    """
  end

  attr :current_user, :map, required: true
  attr :managed_teams, :list, default: []
  attr :member_logins, :list, default: []
  attr :area, :map, default: nil
  attr :id_prefix, :string, default: ""
  attr :email, :boolean, default: false, doc: "show the email, as the phone menu does"

  # The areas you can switch to: Admin, then each of your teams under its name, with its
  # team area if you're one of its team admins and its member area if it lets you log in
  # as a member, then your settings and Log out. The account menu, and the end of the
  # phone menu.
  defp area_links(assigns) do
    assigns =
      assign(assigns, teams: Navigation.menu_teams(assigns.managed_teams, assigns.member_logins))

    ~H"""
    <%= if @current_user.is_admin do %>
      <.a
        id={@id_prefix <> "nav-admin"}
        kind={:custom}
        navigate={~p"/admin"}
        aria-current={in_area?(@area, :admin, nil) && "page"}
      >
        Admin
      </.a>
      <.menu_divider />
    <% end %>
    <%= for %{team: team} = entry <- @teams do %>
      <div class="caps menu-heading">{team.name}</div>
      <.a
        :if={entry.team_area}
        id={@id_prefix <> "nav-team-" <> team.subdomain}
        kind={:custom}
        navigate={~p"/teams/#{team}"}
        aria-current={in_area?(@area, :team, team) && "page"}
      >
        Team area
      </.a>
      <.a
        :if={entry.member_area}
        id={@id_prefix <> "nav-member-" <> team.subdomain}
        kind={:custom}
        navigate={~p"/teams/#{team}/me"}
        aria-current={in_area?(@area, :member, team) && "page"}
      >
        Member area
      </.a>
      <.menu_divider />
    <% end %>
    <div :if={@email} class="menu-note truncate">{@current_user.email}</div>
    <.a
      id={@id_prefix <> "nav-your-settings"}
      kind={:custom}
      navigate={~p"/account"}
      aria-current={in_area?(@area, :settings, nil) && "page"}
    >
      Your settings
    </.a>
    <.a id={@id_prefix <> "nav-log-out"} kind={:custom} method="delete" href="/logout">
      Log out
    </.a>
    """
  end

  defp in_area?(%{kind: kind, team: nil}, kind, nil), do: true
  defp in_area?(%{kind: kind, team: %{id: id}}, kind, %{id: id}), do: true
  defp in_area?(_area, _kind, _team), do: false

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
      <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title="Server disconnected"
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        Reconnecting… <.spinner />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="The page stopped responding"
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        Reconnecting… <.spinner />
      </.flash>
    </div>
    """
  end
end
