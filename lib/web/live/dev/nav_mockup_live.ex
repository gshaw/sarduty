defmodule Web.Dev.NavMockupLive do
  @moduledoc """
  Development only: mockups of the team navigation, to choose one before building it.
  `/dev/nav-mockups?variant=…&as=…&open=…`. Made-up data, no database, no login. Uses the
  app's own top bar, menu, and table styles; the new pieces are in the page's style tag,
  built from the design tokens. Delete once a design is built.
  """
  use Phoenix.LiveView, layout: false

  import Web.Components.A
  import Web.Components.Breadcrumbs
  import Web.Components.Core
  import Web.Components.NavBar
  import Web.Components.Table

  @variants ~w(current sidebar rows grouped more)
  @people ~w(admin manager member members)

  # The team's sections, in groups. A group of one shows as a plain link.
  @groups [
    {nil, [{"Dashboard", "dashboard"}]},
    {"Activities", [{"Activities", "activities"}, {"Templates", "templates"}]},
    {"People",
     [{"Members", "members"}, {"Qualifications", "qualifications"}, {"Groups", "groups"}]},
    {"Equipment", [{"Equipment", "equipment"}]},
    {"Letters", [{"Tax credit letters", "letters"}]}
  ]

  @teams ["Example Valley SAR", "North Shore SAR", "Ridge County SAR"]

  def mount(params, _session, socket) do
    variant = if params["variant"] in @variants, do: params["variant"], else: "sidebar"
    as = if params["as"] in @people, do: params["as"], else: "manager"

    socket =
      assign(socket,
        page_title: "Navigation mockups",
        variant: variant,
        as: as,
        open: params["open"],
        email: "#{as}@example.com",
        admin?: as == "admin",
        member?: as in ~w(member members),
        member_teams: if(as == "members", do: Enum.take(@teams, 2), else: Enum.take(@teams, 1)),
        teams:
          if(as == "admin",
            do: @teams,
            else: if(as == "manager", do: Enum.take(@teams, 1), else: [])
          ),
        groups: @groups,
        current: if(as in ~w(member members), do: "me", else: "templates")
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <style>
      <%= Phoenix.HTML.raw(css()) %>
    </style>
    <.mock_note variant={@variant} as={@as} />
    {bar(assigns)}
    <div class={["mock-body", @variant == "rows" && !@member? && "mock-body-rows"]}>
      <%= if @variant == "sidebar" and !@member? do %>
        <div class="mock-with-sidebar container mx-auto px-2">
          <.sidebar groups={@groups} current={@current} member_page={true} />
          <main class="mock-main"><.templates_page /></main>
        </div>
      <% else %>
        <main class={[if(@member?, do: "mock-narrow", else: "container mx-auto px-2")]}>
          <%= if @member? do %>
            <.member_page />
          <% else %>
            <.templates_page />
          <% end %>
        </main>
      <% end %>
    </div>
    """
  end

  defp bar(%{member?: true} = assigns), do: member_bar(assigns)
  defp bar(%{variant: "current"} = assigns), do: current_bar(assigns)
  defp bar(%{variant: "sidebar"} = assigns), do: sidebar_bar(assigns)
  defp bar(%{variant: "rows"} = assigns), do: rows_bar(assigns)
  defp bar(%{variant: "grouped"} = assigns), do: grouped_bar(assigns)
  defp bar(%{variant: "more"} = assigns), do: more_bar(assigns)

  attr :variant, :string, required: true
  attr :as, :string, required: true

  defp mock_note(assigns) do
    ~H"""
    <div class="mock-note">
      Mockup · {@variant} · {@as}
    </div>
    """
  end

  # Today's bar, for comparison: every section in one row.
  defp current_bar(assigns) do
    ~H"""
    <.site_bar>
      <:links>
        <.a
          :for={{label, key} <- flat(@groups)}
          kind={:custom}
          href="#"
          aria-current={key == @current && "page"}
        >
          {label}
        </.a>
      </:links>
      <.a :if={@admin?} kind={:custom} href="#" class="site-bar-link">Admin</.a>
      <.account email={@email} teams={@teams} open={@open == "account"} member_page="Your ID card" />
    </.site_bar>
    """
  end

  # A: the bar keeps the brand, the team, and the account; sections go down the left.
  defp sidebar_bar(assigns) do
    ~H"""
    <.site_bar>
      <:links>
        <.team_switcher teams={@teams} admin?={@admin?} open={@open == "team"} />
      </:links>
      <.a :if={@admin?} kind={:custom} href="#" class="site-bar-link">Admin</.a>
      <.account email={@email} teams={[]} open={@open == "account"} member_page={nil} />
      <.phone_menu
        groups={@groups}
        current={@current}
        email={@email}
        teams={@teams}
        admin?={@admin?}
        member_teams={@member_teams}
        open={@open == "phone"}
      />
    </.site_bar>
    """
  end

  attr :groups, :list, default: []
  attr :current, :string, required: true
  attr :email, :string, required: true
  attr :teams, :list, default: []
  attr :admin?, :boolean, default: false
  attr :member_teams, :list, default: []
  attr :open, :boolean, default: false

  # Phones: the sidebar and the account menu in one panel behind the Menu button, the
  # sections under the same headings. A member page in the sidebar is the team's own.
  defp phone_menu(assigns) do
    ~H"""
    <details id="phone-menu" class="site-bar-phone group" open={@open}>
      <summary id="phone-menu-button" aria-label="Menu">
        <.icon name="hero-bars-3" class="group-open:hidden" />
        <.icon name="hero-x-mark" class="hidden group-open:inline-block" />
        <span>Menu</span>
      </summary>
      <nav class="site-bar-phone-panel" aria-label="Main">
        <%= if @groups != [] do %>
          <div class="menu-note">{hd(@teams)}</div>
          <%= for {heading, links} <- @groups do %>
            <div :if={heading && length(links) > 1} class="menu-note">{heading}</div>
            <a :for={{label, key} <- links} href="#" aria-current={key == @current && "page"}>
              {label}
            </a>
          <% end %>
          <a href="#">Team settings</a>
          <a href="#">Your member page</a>
          <a :if={@admin?} href="#">Admin</a>
          <hr />
        <% end %>
        <div class="menu-note truncate">{@email}</div>
        <%= if @groups == [] do %>
          <div :if={length(@member_teams) > 1} class="menu-note">Your member pages</div>
          <a
            :for={team <- @member_teams}
            href="#"
            aria-current={team == hd(@member_teams) && "page"}
          >
            {member_page_label(team, @member_teams)}
          </a>
          <hr />
        <% end %>
        <%= if length(@teams) > 1 do %>
          <div class="menu-note">Your teams</div>
          <a :for={team <- @teams} href="#">{team}</a>
          <hr />
        <% end %>
        <a href="#">Account</a>
        <a href="#">Log out</a>
      </nav>
    </details>
    """
  end

  @doc ~s(The link to a member's own page: "Your member page", or the team's name under "Your member pages".)
  def member_page_label(_team, [_one]), do: "Your member page"
  def member_page_label(team, _teams), do: team

  attr :groups, :list, required: true
  attr :current, :string, required: true
  attr :member_page, :boolean, default: false

  defp sidebar(assigns) do
    ~H"""
    <nav class="mock-sidebar" aria-label="Team">
      <%= for {heading, links} <- @groups do %>
        <div class="mock-sidebar-group">
          <div :if={heading && length(links) > 1} class="caps mock-sidebar-heading">{heading}</div>
          <a :for={{label, key} <- links} href="#" aria-current={key == @current && "page"}>
            {label}
          </a>
        </div>
      <% end %>
      <div class="mock-sidebar-group mock-sidebar-end">
        <a href="#">Team settings</a>
        <a :if={@member_page} href="#">Your member page</a>
      </div>
    </nav>
    """
  end

  # B: brand, team, and account on top; every section in a full-width row below.
  defp rows_bar(assigns) do
    ~H"""
    <header class="site-bar mock-rows">
      <div class="site-bar-inner container m-auto px-2">
        <a href="#" class="brand">SAR <span>Duty</span></a>
        <.team_switcher teams={@teams} admin?={@admin?} open={@open == "team"} />
        <div class="flex-1"></div>
        <.a :if={@admin?} kind={:custom} href="#" class="site-bar-link">Admin</.a>
        <.account email={@email} teams={[]} open={@open == "account"} member_page="Your member page" />
      </div>
      <nav class="mock-tabs-row" aria-label="Team">
        <div class="container m-auto px-2 site-bar-links">
          <a
            :for={{label, key} <- flat(@groups) ++ [{"Settings", "settings"}]}
            href="#"
            aria-current={key == @current && "page"}
          >
            {label}
          </a>
        </div>
      </nav>
    </header>
    """
  end

  # C: one row of areas; an area with more than one page opens a short menu.
  defp grouped_bar(assigns) do
    ~H"""
    <.site_bar>
      <:links>
        <%= for {heading, links} <- @groups do %>
          <%= if length(links) == 1 do %>
            <.a
              :for={{label, key} <- links}
              kind={:custom}
              href="#"
              aria-current={key == @current && "page"}
            >
              {if heading, do: heading, else: label}
            </.a>
          <% else %>
            <details class="mock-area relative" open={@open == String.downcase(heading)}>
              <summary aria-current={Enum.any?(links, &(elem(&1, 1) == @current)) && "page"}>
                {heading} <.icon name="hero-chevron-down-micro" />
              </summary>
              <div class="menu mock-menu-left">
                <a :for={{label, key} <- links} href="#" aria-current={key == @current && "page"}>
                  {label}
                </a>
              </div>
            </details>
          <% end %>
        <% end %>
      </:links>
      <.team_switcher teams={@teams} admin?={@admin?} open={@open == "team"} />
      <.a :if={@admin?} kind={:custom} href="#" class="site-bar-link">Admin</.a>
      <.account email={@email} teams={[]} open={@open == "account"} member_page="Your member page" />
    </.site_bar>
    """
  end

  # D: the sections used most stay in the bar; the rest go under More.
  defp more_bar(assigns) do
    {main, rest} =
      assigns.groups
      |> flat()
      |> Enum.split_with(&(elem(&1, 1) in ~w(dashboard activities members equipment)))

    assigns = assign(assigns, main: main, rest: rest)

    ~H"""
    <.site_bar>
      <:links>
        <.a
          :for={{label, key} <- @main}
          kind={:custom}
          href="#"
          aria-current={key == @current && "page"}
        >
          {label}
        </.a>
        <details class="mock-area relative" open={@open == "more"}>
          <summary aria-current={Enum.any?(@rest, &(elem(&1, 1) == @current)) && "page"}>
            More <.icon name="hero-chevron-down-micro" />
          </summary>
          <div class="menu mock-menu-left">
            <a :for={{label, key} <- @rest} href="#" aria-current={key == @current && "page"}>
              {label}
            </a>
          </div>
        </details>
      </:links>
      <.team_switcher teams={@teams} admin?={@admin?} open={@open == "team"} />
      <.a :if={@admin?} kind={:custom} href="#" class="site-bar-link">Admin</.a>
      <.account email={@email} teams={[]} open={@open == "account"} member_page="Your member page" />
    </.site_bar>
    """
  end

  # A member who manages no team: their own page only, as today, in every variant.
  defp member_bar(assigns) do
    ~H"""
    <.site_bar size={:narrow}>
      <.account
        email={@email}
        teams={[]}
        open={@open == "account"}
        member_page="Your member page"
        member_teams={@member_teams}
      />
      <.phone_menu
        current={@current}
        email={@email}
        member_teams={@member_teams}
        open={@open == "phone"}
      />
    </.site_bar>
    """
  end

  attr :teams, :list, required: true
  attr :admin?, :boolean, required: true
  attr :open, :boolean, default: false

  # The team the page is about, and a menu to switch. An admin reaches every team.
  defp team_switcher(assigns) do
    ~H"""
    <details class="mock-team relative" open={@open}>
      <summary>
        <span class="truncate">{hd(@teams)}</span>
        <.icon :if={length(@teams) > 1 or @admin?} name="hero-chevron-down-micro" />
      </summary>
      <div :if={length(@teams) > 1 or @admin?} class="menu mock-menu-left">
        <div class="menu-note">Your teams</div>
        <a :for={team <- @teams} href="#" aria-current={team == hd(@teams) && "page"}>{team}</a>
        <hr :if={@admin?} />
        <a :if={@admin?} href="#">Every team…</a>
      </div>
    </details>
    """
  end

  attr :email, :string, required: true
  attr :teams, :list, default: []
  attr :open, :boolean, default: false
  attr :member_page, :any, default: nil
  attr :member_teams, :list, default: ["Example Valley SAR"]

  defp account(assigns) do
    ~H"""
    <details class="site-bar-menu relative" open={@open}>
      <summary role="button">
        <span class="truncate">{@email}</span>
        <.icon name="hero-chevron-down-micro" />
      </summary>
      <div class="menu">
        <%= if @member_page do %>
          <div :if={length(@member_teams) > 1} class="menu-note">Your member pages</div>
          <a :for={team <- @member_teams} href="#">
            {if length(@member_teams) > 1, do: team, else: @member_page}
          </a>
        <% end %>
        <hr :if={@member_page} />
        <%= if length(@teams) > 1 do %>
          <div class="menu-note">Your teams</div>
          <a :for={team <- @teams} href="#">{team}</a>
          <hr />
        <% end %>
        <a href="#">Account</a>
        <hr />
        <a href="#">Log out</a>
      </div>
    </details>
    """
  end

  defp templates_page(assigns) do
    assigns =
      assign(assigns,
        rows: [
          %{id: 1, title: "Boat training", items: 3, tags: 2, groups: 1},
          %{id: 2, title: "Managers' training", items: 1, tags: 1, groups: 1},
          %{id: 3, title: "Truck 2", items: 2, tags: 0, groups: 0}
        ]
      )

    ~H"""
    <.breadcrumbs team={%App.Model.Team{name: "Example Valley SAR", subdomain: "examplevalley"}}>
      <:item label="Templates" />
    </.breadcrumbs>
    <div class="heading-row">
      <h1 class="title">Templates</h1>
      <.button href="#">Add template</.button>
    </div>
    <p class="lead">
      A template adds items, tags, and invites to an activity in one step. Apply one from the activity's page.
    </p>
    <.table id="mock-templates" rows={@rows} row_id={&"t-#{&1.id}"} class="table-striped">
      <:col :let={row} label="Template">
        <.a href="#">{row.title}</.a>
      </:col>
      <:col :let={row} label="Items" align="right" class="w-px">{row.items}</:col>
      <:col :let={row} label="Tags" align="right" class="w-px">{row.tags}</:col>
      <:col :let={row} label="Groups" align="right" class="w-px">{row.groups}</:col>
    </.table>
    """
  end

  defp member_page(assigns) do
    ~H"""
    <h1 class="heading">Example Valley SAR</h1>
    <p class="lead">Blake Chen</p>
    <h2 class="subheading mt-8">ID card</h2>
    <p>Add your card to Apple Wallet or Google Wallet.</p>
    <h2 class="subheading mt-8">Tax credit letters</h2>
    <p>
      <.a href="#">2025</.a>
      ·
      <.a href="#">2024</.a>
    </p>
    """
  end

  defp flat(groups), do: Enum.flat_map(groups, &elem(&1, 1))

  defp css do
    """
    .mock-note { position: fixed; bottom: var(--sp-2); right: var(--sp-2); z-index: 50; padding: var(--sp-1) var(--sp-2); background: var(--warning); color: var(--on-warning); font-size: var(--fs-xs); border-radius: var(--radius); }
    .mock-body { padding-top: var(--sp-16); }
    .mock-body-rows { padding-top: calc(var(--sp-16) + var(--sp-12)); }
    .mock-narrow { max-width: 28rem; margin: 0 auto; padding: 0 var(--sp-2); }

    .mock-team > summary, .mock-area > summary {
      display: inline-flex; align-items: center; gap: var(--sp-1); list-style: none; cursor: pointer;
      color: #d5dbe3; font-weight: 600; font-size: var(--fs-sm); line-height: var(--lh-sm);
      padding: var(--sp-3) var(--sp-2); white-space: nowrap;
    }
    .mock-team > summary::-webkit-details-marker, .mock-area > summary::-webkit-details-marker { display: none; }
    .mock-team > summary { color: #fff; max-width: 240px; padding: var(--sp-1) var(--sp-2); border-radius: var(--radius); }
    .mock-team > summary:hover { background: rgb(255 255 255 / 0.1); }
    .mock-area > summary:hover { color: #fff; }
    .mock-area > summary[aria-current="page"] { color: #fff; box-shadow: inset 0 -3px var(--accent); }
    .site-bar-links:has(.mock-area, .mock-team) { overflow: visible; }
    .mock-menu-left { left: 0; right: auto; }

    .mock-rows .site-bar-inner { border-bottom: 1px solid rgb(255 255 255 / 0.15); }
    .mock-tabs-row .site-bar-links { overflow-x: auto; }

    .mock-with-sidebar { display: flex; gap: var(--sp-8); }
    .mock-main { flex: 1; min-width: 0; }
    .mock-sidebar { width: 200px; flex-shrink: 0; position: sticky; top: calc(var(--sp-16) + var(--sp-2)); align-self: flex-start; font-size: var(--fs-sm); line-height: var(--lh-sm); }
    .mock-sidebar-group { padding: var(--sp-2) 0; border-bottom: 1px solid var(--border-subtle); }
    .mock-sidebar-group:first-child { padding-top: 0; }
    .mock-sidebar-end { border-bottom: 0; }
    .mock-sidebar-heading { padding: var(--sp-1) var(--sp-3); color: var(--text-muted); }
    .mock-sidebar a { display: block; padding: var(--sp-2) var(--sp-3); color: var(--text); text-decoration: none; border-radius: var(--radius); }
    .mock-sidebar a:hover { background: var(--row-hover); }
    @media (width < 64rem) { .mock-sidebar { display: none; } }
    .mock-sidebar a[aria-current="page"] { font-weight: 700; box-shadow: inset 4px 0 var(--primary); }
    """
  end
end
