defmodule Web.Dev.NavModesMockupLive do
  @moduledoc """
  Development only: one navigation pattern for the three modes, a team, a member, and
  admin. `/dev/nav-mockups/modes?as=…&mode=…&team=…&open=…`. The bar names the mode
  you're in, the sidebar lists that mode's pages, and the account menu switches modes.
  Made-up data, no database, no login. Delete once a design is built.
  """
  use Phoenix.LiveView, layout: false

  import Web.Components.A
  import Web.Components.Breadcrumbs
  import Web.Components.Core
  import Web.Components.NavBar
  import Web.Components.Table

  @teams ["Example Valley SAR", "North Shore SAR"]

  # Who can reach what: the teams they manage, the teams they're a member of, and admin.
  @people %{
    # North Shore has member logins off, so the admin manages it but has no pages there.
    "admin" => %{admin?: true, manages: @teams, member_of: ["Example Valley SAR"]},
    "manager" => %{
      admin?: false,
      manages: ["Example Valley SAR"],
      member_of: ["Example Valley SAR"]
    },
    "member" => %{admin?: false, manages: [], member_of: ["Example Valley SAR"]},
    "members" => %{admin?: false, manages: [], member_of: @teams}
  }

  @team_groups [
    {nil, [{"Dashboard", "dashboard"}]},
    {"Activities", [{"Activities", "activities"}, {"Templates", "templates"}]},
    {"People",
     [{"Members", "members"}, {"Qualifications", "qualifications"}, {"Groups", "groups"}]},
    {"Equipment", [{"Equipment", "equipment"}]},
    {"Letters", [{"Tax credit letters", "letters"}]},
    {nil, [{"Team settings", "settings"}]}
  ]

  @member_groups [
    {nil, [{"Overview", "overview"}, {"Details", "details"}, {"Mobile phone", "mobile"}]}
  ]

  @admin_groups [
    {nil, [{"Dashboard", "dashboard"}]},
    {"Teams", [{"Teams", "teams"}, {"Organizations", "orgs"}, {"ID cards", "cards"}]},
    {"SAR Duty", [{"Admins", "admins"}, {"MCP", "mcp"}, {"Events", "events"}]}
  ]

  def mount(params, _session, socket) do
    as = if Map.has_key?(@people, params["as"]), do: params["as"], else: "manager"
    person = @people[as]
    mode = pick_mode(params["mode"], person)
    team = pick_team(params["team"], mode, person)

    socket =
      assign(socket,
        page_title: "Navigation modes mockup",
        as: as,
        email: "#{as}@example.com",
        person: person,
        mode: mode,
        team: team,
        open: params["open"],
        groups: groups(mode),
        current: current(mode)
      )

    {:ok, socket}
  end

  defp pick_mode(mode, person) when mode in ~w(team member admin) do
    cond do
      mode == "team" and person.manages != [] -> mode
      mode == "member" and person.member_of != [] -> mode
      mode == "admin" and person.admin? -> mode
      true -> default_mode(person)
    end
  end

  defp pick_mode(_mode, person), do: default_mode(person)

  defp default_mode(%{manages: [_ | _]}), do: "team"
  defp default_mode(_person), do: "member"

  defp pick_team(team, "team", person),
    do: if(team in person.manages, do: team, else: hd(person.manages))

  defp pick_team(team, "member", person),
    do: if(team in person.member_of, do: team, else: hd(person.member_of))

  defp pick_team(_team, "admin", _person), do: nil

  defp groups("team"), do: @team_groups
  defp groups("member"), do: @member_groups
  defp groups("admin"), do: @admin_groups

  defp current("team"), do: "templates"
  defp current("member"), do: "overview"
  defp current("admin"), do: "teams"

  @doc ~s(The mode, as the bar shows it: {"Example Valley SAR", "Team"}, or {"Admin", nil}.)
  def mode_label("team", team), do: {team, "Team"}
  def mode_label("member", team), do: {team, "Member"}
  def mode_label("admin", _team), do: {"Admin", nil}

  def render(assigns) do
    ~H"""
    <style>
      <%= Phoenix.HTML.raw(css()) %>
    </style>
    <div class="mock-note">Mockup · modes · {@as} · {@mode}</div>
    <.site_bar>
      <:links>
        <.mode_name mode={@mode} team={@team} />
      </:links>
      <.account_menu
        person={@person}
        email={@email}
        mode={@mode}
        team={@team}
        open={@open == "account"}
      />
      <.phone_menu
        person={@person}
        email={@email}
        mode={@mode}
        team={@team}
        groups={@groups}
        current={@current}
        open={@open == "phone"}
      />
    </.site_bar>
    <div class="mock-body container mx-auto px-2">
      <div class="mock-with-sidebar">
        <.sidebar groups={@groups} current={@current} />
        <main class="mock-main">
          <.page mode={@mode} team={@team} />
        </main>
      </div>
    </div>
    """
  end

  attr :mode, :string, required: true
  attr :team, :string, default: nil

  defp mode_name(assigns) do
    assigns = assign(assigns, label: mode_label(assigns.mode, assigns.team))

    ~H"""
    <span class="mock-mode">
      {elem(@label, 0)}
      <span :if={elem(@label, 1)} class="mock-mode-kind">{elem(@label, 1)}</span>
    </span>
    """
  end

  attr :person, :map, required: true
  attr :mode, :string, required: true
  attr :team, :string, default: nil

  # Every mode the person can switch to: admin, then each of their teams under its name,
  # with Team area if they manage it and Member area if it has member logins, then their
  # account. Teams A to Z.
  defp mode_links(assigns) do
    assigns =
      assign(assigns,
        teams: (assigns.person.manages ++ assigns.person.member_of) |> Enum.uniq() |> Enum.sort()
      )

    ~H"""
    <%= if @person.admin? do %>
      <a href="#" aria-current={@mode == "admin" && "page"}>Admin</a>
      <hr />
    <% end %>
    <%= for team <- @teams do %>
      <div class="mock-menu-team">{team}</div>
      <a
        :if={team in @person.manages}
        href="#"
        aria-current={(@mode == "team" and @team == team) && "page"}
      >
        Team area
      </a>
      <a
        :if={team in @person.member_of}
        href="#"
        aria-current={(@mode == "member" and @team == team) && "page"}
      >
        Member area
      </a>
      <hr />
    <% end %>
    <a href="#">Account</a>
    <a href="#">Log out</a>
    """
  end

  attr :person, :map, required: true
  attr :email, :string, required: true
  attr :mode, :string, required: true
  attr :team, :string, default: nil
  attr :open, :boolean, default: false

  defp account_menu(assigns) do
    ~H"""
    <details class="site-bar-menu relative" open={@open}>
      <summary role="button">
        <span class="truncate">{@email}</span>
        <.icon name="hero-chevron-down-micro" />
      </summary>
      <div class="menu">
        <.mode_links person={@person} mode={@mode} team={@team} />
      </div>
    </details>
    """
  end

  attr :person, :map, required: true
  attr :email, :string, required: true
  attr :mode, :string, required: true
  attr :team, :string, default: nil
  attr :groups, :list, required: true
  attr :current, :string, required: true
  attr :open, :boolean, default: false

  # Phones: this mode's sidebar first, then the account menu's list.
  defp phone_menu(assigns) do
    assigns = assign(assigns, label: mode_label(assigns.mode, assigns.team))

    ~H"""
    <details id="phone-menu" class="site-bar-phone group" open={@open}>
      <summary id="phone-menu-button" aria-label="Menu">
        <.icon name="hero-bars-3" class="group-open:hidden" />
        <.icon name="hero-x-mark" class="hidden group-open:inline-block" />
        <span>Menu</span>
      </summary>
      <nav class="site-bar-phone-panel" aria-label="Main">
        <div class="menu-note">
          {elem(@label, 0)}{if elem(@label, 1), do: " · #{elem(@label, 1)}"}
        </div>
        <%= for {heading, links} <- @groups do %>
          <div :if={heading && length(links) > 1} class="menu-note">{heading}</div>
          <a :for={{label, key} <- links} href="#" aria-current={key == @current && "page"}>
            {label}
          </a>
        <% end %>
        <hr />
        <div class="menu-note truncate">{@email}</div>
        <.mode_links person={@person} mode={@mode} team={@team} />
      </nav>
    </details>
    """
  end

  attr :groups, :list, required: true
  attr :current, :string, required: true

  # The same sidebar in every mode; only its links change.
  defp sidebar(assigns) do
    ~H"""
    <nav class="mock-sidebar" aria-label="Pages">
      <div :for={{heading, links} <- @groups} class="mock-sidebar-group">
        <div :if={heading && length(links) > 1} class="caps mock-sidebar-heading">{heading}</div>
        <a :for={{label, key} <- links} href="#" aria-current={key == @current && "page"}>
          {label}
        </a>
      </div>
    </nav>
    """
  end

  attr :mode, :string, required: true
  attr :team, :string, default: nil

  defp page(%{mode: "team"} = assigns) do
    assigns =
      assign(assigns,
        rows: [
          %{id: 1, title: "Boat training", items: 3, tags: 2, groups: 1},
          %{id: 2, title: "Managers' training", items: 1, tags: 1, groups: 1},
          %{id: 3, title: "Truck 2", items: 2, tags: 0, groups: 0}
        ]
      )

    ~H"""
    <.breadcrumbs team={%App.Model.Team{name: @team, subdomain: "examplevalley"}}>
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

  defp page(%{mode: "member"} = assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">{@team}</h1>
      <p class="lead">Blake Chen</p>
      <h2 class="heading mt-8">ID card</h2>
      <p>Add your card to Apple Wallet or Google Wallet.</p>
      <h2 class="heading mt-8">Tax credit letters</h2>
      <p>
        <.a href="#">2025</.a>
        ·
        <.a href="#">2024</.a>
      </p>
      <h2 class="heading mt-8">Hours</h2>
      <p>212 hours in 2025.</p>
    </div>
    """
  end

  defp page(%{mode: "admin"} = assigns) do
    assigns =
      assign(assigns,
        rows: [
          %{id: 1, name: "Example Valley SAR", members: 84, refreshed: "Oct 13, 2026"},
          %{id: 2, name: "North Shore SAR", members: 112, refreshed: "Oct 13, 2026"},
          %{id: 3, name: "Ridge County SAR", members: 41, refreshed: "Oct 12, 2026"}
        ]
      )

    ~H"""
    <h1 class="title">Teams</h1>
    <.table id="mock-teams" rows={@rows} row_id={&"team-#{&1.id}"} class="table-striped">
      <:col :let={row} label="Team">
        <.a href="#">{row.name}</.a>
      </:col>
      <:col :let={row} label="Members" align="right" class="w-px">{row.members}</:col>
      <:col :let={row} label="Refreshed" class="w-px whitespace-nowrap">{row.refreshed}</:col>
    </.table>
    """
  end

  defp css do
    """
    .mock-note { position: fixed; bottom: var(--sp-2); right: var(--sp-2); z-index: 50; padding: var(--sp-1) var(--sp-2); background: var(--warning); color: var(--on-warning); font-size: var(--fs-xs); border-radius: var(--radius); }
    .mock-body { padding-top: var(--sp-16); }
    .menu .mock-menu-team { padding: var(--sp-2) var(--sp-4) 0; font-weight: 700; color: var(--text); }
    .site-bar-phone-panel .mock-menu-team { padding: var(--sp-2) var(--sp-4) 0; font-weight: 700; color: #fff; font-size: var(--fs-sm); line-height: var(--lh-sm); }
    .mock-mode { display: inline-flex; align-items: baseline; gap: var(--sp-2); color: #fff; font-weight: 600; font-size: var(--fs-md); line-height: var(--lh-md); white-space: nowrap; padding: var(--sp-3) var(--sp-2); }
    .mock-mode-kind { color: #d5dbe3; font-weight: 400; font-size: var(--fs-sm); line-height: var(--lh-sm); }

    .mock-with-sidebar { display: flex; gap: var(--sp-8); }
    .mock-main { flex: 1; min-width: 0; }
    .mock-sidebar { width: 200px; flex-shrink: 0; position: sticky; top: calc(var(--sp-16) + var(--sp-2)); align-self: flex-start; font-size: var(--fs-sm); line-height: var(--lh-sm); }
    .mock-sidebar-group { padding: var(--sp-2) 0; border-bottom: 1px solid var(--border-subtle); }
    .mock-sidebar-group:first-child { padding-top: 0; }
    .mock-sidebar-group:last-child { border-bottom: 0; }
    .mock-sidebar-heading { padding: var(--sp-1) var(--sp-3); }
    .mock-sidebar a { display: block; padding: var(--sp-2) var(--sp-3); color: var(--text); text-decoration: none; border-radius: var(--radius); }
    .mock-sidebar a:hover { background: var(--row-hover); }
    .mock-sidebar a[aria-current="page"] { font-weight: 700; box-shadow: inset 4px 0 var(--primary); }
    @media (width < 64rem) { .mock-sidebar { display: none; } }
    """
  end
end
