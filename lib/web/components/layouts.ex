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

  # Team and admin pages put their area's pages down the left. Account settings has one
  # page, so no side navigation. No footer: its links are for visitors, and the public
  # pages have it.
  def app(assigns) do
    {area, sections} = assigns |> nav_assigns() |> navigation()
    assigns = assign(assigns, nav_area: area, nav_sections: sections)

    ~H"""
    <.main_nav_bar {nav_assigns(assigns)}>
      <:search :if={match?(%{kind: :team}, @nav_area)}>
        <.live_component
          module={Web.Components.SearchBox}
          id="search"
          team={@nav_area.team}
          team_admin?={assigns[:team_admin?] || false}
          member?={assigns[:current_member] != nil}
          sections={@nav_sections}
          user_id={@current_user.id}
        />
      </:search>
    </.main_nav_bar>
    <%= if @nav_sections != [] do %>
      <div class="with-side-nav container mx-auto pt-16 px-2 mb-8">
        <.area_side_nav area={@nav_area} sections={@nav_sections} />
        <main role="main" class="side-nav-main">
          <.view_as_banner
            :if={assigns[:viewing_as]}
            member={@viewing_as}
            team={@current_team}
            team_admin?={@team_admin?}
          />
          <.flash_group flash={@flash} />
          {@inner_content}
        </main>
      </div>
    <% else %>
      <main role="main" class="container mx-auto pt-16 px-2 mb-8">
        <.view_as_banner
          :if={assigns[:viewing_as]}
          member={@viewing_as}
          team={@current_team}
          team_admin?={@team_admin?}
        />
        <.flash_group flash={@flash} />
        {@inner_content}
      </main>
    <% end %>
    <.dev_footer />
    """
  end

  attr :member, :map, required: true
  attr :team, :map, required: true
  attr :team_admin?, :boolean, required: true

  # On every team page while a team admin views as a member (#425), with the way out.
  # Team admin pages stay the team admin's, and say so.
  defp view_as_banner(assigns) do
    ~H"""
    <.banner kind={:warning} title={"Viewing as #{@member.name}"} id="view-as-banner" class="mb-6">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <p :if={!@team_admin?} class="mb-0">
          This is what {@member.name} sees. Nothing you do here is saved or sent to D4H.
        </p>
        <p :if={@team_admin?} class="mb-0">
          This page is yours as a team admin. Pages members see show what {@member.name} sees.
        </p>
        <.button id="view-as-stop" href={~p"/teams/#{@team}/view-as"} method="delete">
          Stop viewing
        </.button>
      </div>
    </.banner>
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
        <a :if={@organization.website} href={@organization.website} class="hover:underline">{@organization.name}</a>
        <span :if={!@organization.website}>{@organization.name}</span> ·
      </span>
      Powered by <a href={Web.Endpoint.url()} class="hover:underline">{Web.Endpoint.host()}</a>
      ·
      <a id="verify-footer-privacy" href={Web.Endpoint.url() <> "/privacy"} class="hover:underline">Privacy</a>
      ·
      <a id="verify-footer-terms" href={Web.Endpoint.url() <> "/terms"} class="hover:underline">Terms</a>
    </footer>
    """
  end

  # One task done with a phone or iPad in hand, such as logging in: one centred column at
  # every width under the compact bar, and no footer links to wander off to. narrow_tool is
  # the wider column, for a tool with a list. See /styles/layout.
  def narrow(assigns), do: narrow_page(assign(assigns, :size, :form))
  def narrow_tool(assigns), do: narrow_page(assign(assigns, :size, :tool))

  defp narrow_page(assigns) do
    ~H"""
    <.main_nav_bar {nav_assigns(assigns)} size={@size} />
    <main role="main" class={["m-auto px-2 pt-16 mb-8", column_width(@size)]}>
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    <.dev_footer size={@size} />
    """
  end

  @doc "The column a size of page stops at: the narrow layout's two, or the app's container."
  def column_width(:form), do: "max-w-md"
  def column_width(:tool), do: "max-w-3xl"
  def column_width(:wide), do: "container"

  attr :size, :atom, values: ~w(wide form tool)a, default: :wide

  # App and login pages have no footer, but in dev the mailbox is where login codes go.
  defp dev_footer(assigns) do
    assigns =
      assign(assigns,
        dev_routes?: Application.get_env(:sarduty, :dev_routes) == true,
        mailbox?: dev_mailbox?()
      )

    ~H"""
    <footer
      :if={@dev_routes?}
      id="dev-footer"
      class={["m-auto px-2 mb-8 text-sm", column_width(@size)]}
    >
      <p class="pt-4 border-t border-border-subtle">
        Development: <.a href="/dev/dashboard" external={true}>Dashboard</.a>
        <%= if @mailbox? do %>
          · <.a href="/dev/mailbox" external={true}>Mailbox</.a>
        <% end %>
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

  # The public pages' footer. The verify site is a separate host, so its link is a full URL.
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
        · <.a id="footer-terms" navigate={~p"/terms"}>Terms</.a>
        · <.a id="footer-privacy" navigate={~p"/privacy"}>Privacy</.a>
        <%= if @admin? do %>
          · <.a id="footer-styles" href="/styles">Style guide</.a>
          · <.a href="https://github.com/gshaw/sarduty" external={true}>GitHub</.a>
        <% end %>
        <%= if @dev_routes? do %>
          · <.a href="/dev/dashboard" external={true}>Dashboard</.a>
          <%= if @mailbox? do %>
            · <.a href="/dev/mailbox" external={true}>Mailbox</.a>
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
      current_member: assigns[:current_member],
      viewing_as: assigns[:viewing_as],
      team_admin?: assigns[:team_admin?] || false,
      managed_teams: assigns[:managed_teams] || [],
      member_logins: assigns[:member_logins] || [],
      current_path: assigns[:current_path],
      proposed_change_count: assigns[:proposed_change_count] || 0,
      chore_count: assigns[:chore_count] || 0
    }
  end

  # The page's area and its pages, for the bar, the side navigation, and the phone menu.
  # Web.Navigation decides both.
  defp navigation(assigns) do
    area = Navigation.area(assigns.current_path, assigns.current_team)

    sections =
      Navigation.sections(area, assigns.current_path,
        team_admin?: assigns.team_admin?,
        member?: assigns.current_member != nil,
        proposed_changes: assigns.proposed_change_count,
        chores: assigns.chore_count
      )

    {area, sections}
  end

  attr :current_user, :map, default: nil
  attr :current_team, :map, default: nil
  attr :current_member, :map, default: nil
  attr :viewing_as, :map, default: nil
  attr :team_admin?, :boolean, default: false
  attr :managed_teams, :list, default: []
  attr :member_logins, :list, default: []
  attr :current_path, :string, default: nil
  attr :proposed_change_count, :integer, default: 0
  attr :chore_count, :integer, default: 0
  attr :size, :atom, default: :wide

  slot :search,
    doc: "the search, before the avatar (#473): a field on a desktop, an icon below 1024px"

  # The top bar (#406): the area's name after the logo, with the team switcher on it when
  # you can go somewhere else, and your avatar on the right, which opens the account menu.
  # Outside every area (home, terms, privacy), a logged-in person's bar names their team,
  # with the switcher on it and nothing marked, so the name always opens the way back.
  # Below 1024px (#471) the Menu button on the left holds the area's pages, the logo sits
  # over the area's name in the middle, with the switcher on the name, and the avatar stays
  # on the right. Its menus share one details name, so opening one closes the others.
  # See /styles/top-bar.
  def main_nav_bar(assigns) do
    {area, sections} = navigation(assigns)

    {switch_rows, person} =
      if user = assigns.current_user do
        {Navigation.switch_rows(
           user.is_admin,
           assigns.managed_teams,
           assigns.member_logins,
           area
         ), Navigation.person(user, own_member(assigns), assigns.member_logins)}
      else
        {[], nil}
      end

    bar_area =
      area ||
        Navigation.outside_area(
          assigns.current_user,
          assigns.current_team,
          assigns.member_logins
        )

    assigns =
      assign(assigns,
        bar_area: bar_area,
        sections: sections,
        switch_rows: switch_rows,
        person: person
      )

    ~H"""
    <.site_bar size={@size}>
      <:links :if={@bar_area}>
        <.team_switcher :if={@switch_rows != []} name={@bar_area.name} rows={@switch_rows} />
        <span :if={@switch_rows == []} id="nav-area" class="site-bar-area">{@bar_area.name}</span>
      </:links>
      <%= if @current_user do %>
        <div :if={@bar_area} id="phone-nav-area" class="site-bar-area-phone">
          <a href="/" class="brand">SAR <span>Duty</span></a>
          <details
            :if={@switch_rows != []}
            id="phone-team-switcher"
            name="site-bar"
            class="phone-team-switcher group"
          >
            <summary aria-label={"#{@bar_area.name}, switch team"}>
              <span class="site-bar-area-name">{@bar_area.name}</span>
              <.icon name="hero-chevron-down-micro" class="group-open:rotate-180" />
            </summary>
            <nav class="site-bar-phone-panel" aria-label="Switch team">
              <.switch_menu rows={@switch_rows} id_prefix="phone-switch-" />
            </nav>
          </details>
          <span :if={@switch_rows == []} class="site-bar-area-name">{@bar_area.name}</span>
        </div>
        <div class="site-bar-end">
          {render_slot(@search)}
          <.account_menu person={@person} />
        </div>
        <.site_bar_phone_menu
          :if={@sections != []}
          waiting?={Enum.any?(List.flatten(@sections), & &1.count)}
        >
          <%= for {links, index} <- Enum.with_index(@sections) do %>
            <.menu_divider :if={index > 0} />
            <.nav_link :for={link <- links} link={link} id_prefix="phone-nav-" />
          <% end %>
        </.site_bar_phone_menu>
      <% else %>
        <.a
          :if={!login_page?(@current_path)}
          id="nav-login"
          kind={:custom}
          navigate={~p"/login"}
          class="site-bar-login"
        ><.icon name="hero-arrow-right-end-on-rectangle" /> Log in</.a>
      <% end %>
    </.site_bar>
    """
  end

  # On the login pages the page's own button is Log in, so the bar doesn't repeat it.
  defp login_page?(path), do: path in ["/login", "/login/code"]

  # Who the account menu shows: the person logged in, never the member they view as.
  defp own_member(%{viewing_as: nil} = assigns), do: assigns.current_member

  defp own_member(assigns) do
    Enum.find(assigns.member_logins, &(&1.team_id == assigns.current_team.id))
  end

  attr :name, :string, required: true
  attr :rows, :list, required: true, doc: "from Web.Navigation.switch_rows/4"

  # The area's name with a chevron, opening a menu of the places you can switch to.
  defp team_switcher(assigns) do
    ~H"""
    <details id="team-switcher" name="site-bar" class="site-bar-menu team-switcher relative">
      <summary id="nav-area" aria-label={"#{@name}, switch team"}>
        <span class="truncate">{@name}</span>
        <.icon name="hero-chevron-down-micro" />
      </summary>
      <div class="menu" role="menu">
        <.switch_menu rows={@rows} id_prefix="switch-" />
      </div>
    </details>
    """
  end

  attr :rows, :list, required: true, doc: "from Web.Navigation.switch_rows/4"
  attr :id_prefix, :string, required: true

  # The switcher's rows, in the bar's menu or the phone's panel: Your teams, then SAR Duty
  # admin below a divider with its shield, so it never reads as one more team.
  defp switch_menu(assigns) do
    {admin, teams} = Enum.split_with(assigns.rows, &(&1.kind == :admin))
    assigns = assign(assigns, admin: admin, teams: teams)

    ~H"""
    <%= if @teams != [] do %>
      <div class="caps menu-heading">Your teams</div>
      <.switch_link :for={row <- @teams} row={row} id_prefix={@id_prefix} />
    <% end %>
    <.menu_divider :if={@teams != [] and @admin != []} />
    <.switch_link :for={row <- @admin} row={row} id_prefix={@id_prefix} />
    """
  end

  attr :row, :map, required: true
  attr :id_prefix, :string, required: true

  defp switch_link(assigns) do
    ~H"""
    <.link
      navigate={@row.path}
      id={@id_prefix <> @row.key}
      aria-current={@row.current && "page"}
      class={["nav-link", @row.kind == :admin && "switch-admin"]}
    >
      <.icon :if={@row.kind == :admin} name="hero-shield-check-micro" />
      {@row.label}
    </.link>
    """
  end

  attr :person, :map, required: true, doc: "from Web.Navigation.person/3"

  # Your avatar, top right at every width, opening your name and email, Account settings,
  # and Log out. The same on every team: it is about the login, not the team.
  defp account_menu(assigns) do
    ~H"""
    <details id="account-menu" name="site-bar" class="site-bar-menu account-menu relative">
      <summary aria-label="Your account">
        <span class="avatar">{@person.initials}</span>
      </summary>
      <div class="menu" role="menu">
        <div class="menu-person">
          <span class="avatar">{@person.initials}</span>
          <div class="min-w-0">
            <div :if={@person.name} class="menu-name truncate">{@person.name}</div>
            <div class="menu-note truncate">{@person.email}</div>
          </div>
        </div>
        <.menu_divider />
        <.a id="nav-account-settings" kind={:custom} navigate={~p"/account"}>Account settings</.a>
        <.menu_divider />
        <.a id="nav-log-out" kind={:custom} method="delete" href="/logout">Log out</.a>
      </div>
    </details>
    """
  end

  attr :area, :map, required: true, doc: "from Web.Navigation.area/2"
  attr :sections, :list, required: true, doc: "from Web.Navigation.sections/3"

  @doc "The area's pages down the left, as the app layout shows them. See /styles/side-nav."
  def area_side_nav(assigns) do
    ~H"""
    <.side_nav label={@area.name}>
      <:section :for={links <- @sections}>
        <.nav_link :for={link <- links} link={link} id_prefix="side-nav-" />
      </:section>
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
