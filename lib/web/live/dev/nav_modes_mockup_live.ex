defmodule Web.Dev.NavModesMockupLive do
  @moduledoc """
  Development only: one navigation pattern for the three areas, a team's, a member's, and
  admin, plus the account page. `/dev/nav-mockups/modes?as=…&mode=…&page=…&team=…&open=…`.
  The bar names the area you're in, the sidebar lists that area's pages, and the account
  menu switches areas. Made-up data, no database, no login. Delete once a design is built.
  """
  use Phoenix.LiveView, layout: false

  import Web.Components.A
  import Web.Components.Core
  import Web.Components.NavBar
  import Web.Components.Table

  @teams ["Example Valley SAR", "North Shore SAR"]

  # A team an admin opens from Admin → Teams without being on it.
  @visited "Ridge County SAR"

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

  # A link is {label, key}, or {label, key, count} with a count of things waiting.
  @team_groups [
    {nil, [{"Dashboard", "dashboard"}]},
    {"Activities",
     [
       {"Activities", "activities"},
       {"Templates", "templates"},
       {"Proposed changes", "proposed", 2}
     ]},
    {"People",
     [{"Members", "members"}, {"Qualifications", "qualifications"}, {"Groups", "groups"}]},
    {"Equipment", [{"Equipment", "equipment"}]},
    {"Letters", [{"Tax credit letters", "letters"}]},
    {"Settings",
     [
       {"General", "general"},
       {"ID cards", "cards"},
       {"Team admins", "team-admins"},
       {"Member logins", "member-logins"},
       {"MCP tokens", "mcp"}
     ]}
  ]

  @member_groups [
    {nil, [{"Overview", "overview"}, {"Contact details", "details"}, {"Mobile number", "mobile"}]}
  ]

  @admin_groups [
    {nil, [{"Teams", "teams"}, {"Organizations", "orgs"}, {"ID cards", "cards"}]},
    {"SAR Duty", [{"Admins", "admins"}, {"Events", "events"}, {"MCP", "mcp"}]}
  ]

  # Each area's pages in the mockup, the first its default, and the sidebar link each marks.
  @pages %{
    "team" => [
      {"activity", "activities"},
      {"member", "members"},
      {"logins", "member-logins"},
      {"templates", "templates"}
    ],
    "member" => [{"overview", "overview"}, {"details", "details"}],
    "admin" => [{"teams", "teams"}],
    "account" => [{"account", nil}]
  }

  def mount(params, _session, socket) do
    as = if Map.has_key?(@people, params["as"]), do: params["as"], else: "manager"
    person = @people[as]
    mode = pick_mode(params["mode"], person)
    team = pick_team(params["team"], mode, person)
    {page, current} = pick_page(params["page"], mode)

    socket =
      assign(socket,
        page_title: "Navigation modes mockup",
        as: as,
        email: "#{as}@example.com",
        person: person,
        mode: mode,
        team: team,
        page: page,
        current: current,
        visited: if(mode == "team" and team not in person.manages, do: team),
        open: params["open"],
        groups: groups(mode)
      )

    {:ok, socket}
  end

  defp pick_mode(mode, person),
    do: if(may_use?(mode, person), do: mode, else: default_mode(person))

  defp may_use?("team", person), do: person.manages != [] or person.admin?
  defp may_use?("member", person), do: person.member_of != []
  defp may_use?("admin", person), do: person.admin?
  defp may_use?("account", _person), do: true
  defp may_use?(_mode, _person), do: false

  defp default_mode(%{manages: [_ | _]}), do: "team"
  defp default_mode(_person), do: "member"

  defp pick_team(@visited, "team", %{admin?: true}), do: @visited

  defp pick_team(team, "team", person),
    do: if(team in person.manages, do: team, else: hd(person.manages))

  defp pick_team(team, "member", person),
    do: if(team in person.member_of, do: team, else: hd(person.member_of))

  defp pick_team(_team, _mode, _person), do: nil

  defp pick_page(page, mode) do
    pages = @pages[mode]
    List.keyfind(pages, page, 0) || hd(pages)
  end

  defp groups("team"), do: @team_groups
  defp groups("member"), do: @member_groups
  defp groups("admin"), do: @admin_groups
  defp groups("account"), do: []

  @doc ~s(The area, as the bar shows it: {"Example Valley SAR", "Team"}, or {"Admin", nil}.)
  def mode_label("team", team), do: {team, "Team"}
  def mode_label("member", team), do: {team, "Member"}
  def mode_label("admin", _team), do: {"Admin", nil}
  def mode_label("account", _team), do: {"Account", nil}

  defp bar_label(%{mode: mode, team: team, visited: nil}), do: mode_label(mode, team)

  defp bar_label(%{mode: mode, team: team}),
    do: {team, "#{elem(mode_label(mode, team), 1)}, as an admin"}

  def render(assigns) do
    ~H"""
    <style>
      <%= Phoenix.HTML.raw(css()) %>
    </style>
    <div class="mock-note">Mockup · {@as} · {@mode} · {@page}</div>
    <.site_bar>
      <:links>
        <.mode_name mode={@mode} team={@team} visited={@visited} />
      </:links>
      <.account_menu
        person={@person}
        email={@email}
        mode={@mode}
        team={@team}
        visited={@visited}
        open={@open == "account"}
      />
      <.phone_mode_name mode={@mode} team={@team} visited={@visited} />
      <.phone_menu
        person={@person}
        email={@email}
        mode={@mode}
        team={@team}
        visited={@visited}
        groups={@groups}
        current={@current}
        open={@open == "phone"}
      />
    </.site_bar>
    <div class="mock-body container mx-auto px-2">
      <%= if @groups == [] do %>
        <main class="measure"><.page mode={@mode} page={@page} team={@team} email={@email} /></main>
      <% else %>
        <div class="mock-with-sidebar">
          <.sidebar groups={@groups} current={@current} />
          <main class="mock-main">
            <.page mode={@mode} page={@page} team={@team} email={@email} />
          </main>
        </div>
      <% end %>
    </div>
    """
  end

  attr :mode, :string, required: true
  attr :team, :string, default: nil
  attr :visited, :string, default: nil

  # The area's name in the bar. It goes to the area's first page. An admin on a team they
  # aren't on sees that, since changes there still go to the team's D4H.
  defp mode_name(assigns) do
    assigns = assign(assigns, label: bar_label(assigns))

    ~H"""
    <a href="#" class="mock-mode">
      {elem(@label, 0)}
      <span :if={elem(@label, 1)} class="mock-mode-kind">{elem(@label, 1)}</span>
    </a>
    """
  end

  attr :mode, :string, required: true
  attr :team, :string, default: nil
  attr :visited, :string, default: nil

  # Phones: the same name beside the brand, the area under it, so you know where you are
  # without opening the menu.
  defp phone_mode_name(assigns) do
    assigns = assign(assigns, label: bar_label(assigns))

    ~H"""
    <a href="#" class="mock-mode-phone">
      <span class="truncate">{elem(@label, 0)}</span>
      <span :if={elem(@label, 1)} class="mock-mode-phone-kind">{elem(@label, 1)}</span>
    </a>
    """
  end

  attr :person, :map, required: true
  attr :mode, :string, required: true
  attr :team, :string, default: nil
  attr :visited, :string, default: nil
  attr :email, :string, default: nil, doc: "shown above Account on a phone"

  # Every area the person can switch to: admin, then each of their teams under its name,
  # with Team area if they manage it and Member area if it has member logins, then their
  # account. Teams A to Z. A team an admin is visiting joins the list while they're in it.
  defp mode_links(assigns) do
    teams = assigns.person.manages ++ assigns.person.member_of ++ List.wrap(assigns.visited)
    assigns = assign(assigns, teams: teams |> Enum.uniq() |> Enum.sort())

    ~H"""
    <%= if @person.admin? do %>
      <a href="#" aria-current={@mode == "admin" && "page"}>Admin</a>
      <hr />
    <% end %>
    <%= for team <- @teams do %>
      <div class="mock-menu-team">{team}</div>
      <div :if={team == @visited} class="menu-note mock-menu-visit">As an admin</div>
      <a
        :if={team in @person.manages or team == @visited}
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
    <div :if={@email} class="menu-note truncate">{@email}</div>
    <a href="#" aria-current={@mode == "account" && "page"}>Account</a>
    <a href="#">Log out</a>
    """
  end

  attr :person, :map, required: true
  attr :email, :string, required: true
  attr :mode, :string, required: true
  attr :team, :string, default: nil
  attr :visited, :string, default: nil
  attr :open, :boolean, default: false

  defp account_menu(assigns) do
    ~H"""
    <details class="site-bar-menu relative" open={@open}>
      <summary role="button">
        <span class="truncate">{@email}</span>
        <.icon name="hero-chevron-down-micro" />
      </summary>
      <div class="menu">
        <.mode_links person={@person} mode={@mode} team={@team} visited={@visited} />
      </div>
    </details>
    """
  end

  attr :person, :map, required: true
  attr :email, :string, required: true
  attr :mode, :string, required: true
  attr :team, :string, default: nil
  attr :visited, :string, default: nil
  attr :groups, :list, required: true
  attr :current, :string, default: nil
  attr :open, :boolean, default: false

  # Phones: this area's sidebar first, then the account menu's list.
  defp phone_menu(assigns) do
    ~H"""
    <details id="phone-menu" class="site-bar-phone group" open={@open}>
      <summary id="phone-menu-button" aria-label="Menu">
        <.icon name="hero-bars-3" class="group-open:hidden" />
        <.icon name="hero-x-mark" class="hidden group-open:inline-block" />
        <span>Menu</span>
      </summary>
      <nav class="site-bar-phone-panel" aria-label="Main">
        <%= for {heading, links} <- @groups do %>
          <div :if={heading && length(links) > 1} class="menu-note">{heading}</div>
          <a :for={link <- links} href="#" aria-current={elem(link, 1) == @current && "page"}>
            <.link_text link={link} />
          </a>
        <% end %>
        <hr :if={@groups != []} />
        <.mode_links
          person={@person}
          mode={@mode}
          team={@team}
          visited={@visited}
          email={@email}
        />
      </nav>
    </details>
    """
  end

  attr :groups, :list, required: true
  attr :current, :string, default: nil

  # The same sidebar in every area; only its links change.
  defp sidebar(assigns) do
    ~H"""
    <nav class="mock-sidebar" aria-label="Pages">
      <div :for={{heading, links} <- @groups} class="mock-sidebar-group">
        <div :if={heading && length(links) > 1} class="caps mock-sidebar-heading">{heading}</div>
        <a :for={link <- links} href="#" aria-current={elem(link, 1) == @current && "page"}>
          <.link_text link={link} />
        </a>
      </div>
    </nav>
    """
  end

  attr :link, :any, required: true

  # A link's label, and its count when something waits there.
  defp link_text(%{link: {label, _key, count}} = assigns) do
    assigns = assign(assigns, label: label, count: count)

    ~H"""
    <span class="mock-link-row">
      {@label}
      <.badge kind={:warning} title="Waiting for a team admin">{@count}</.badge>
    </span>
    """
  end

  defp link_text(%{link: {label, _key}} = assigns) do
    assigns = assign(assigns, label: label)

    ~H"""
    {@label}
    """
  end

  slot :item, required: true

  # Breadcrumbs start at the section: the bar already names the team. The last item is
  # the page you're on.
  defp crumbs(assigns) do
    ~H"""
    <ol class="breadcrumbs">
      <%= for {item, i} <- Enum.with_index(@item) do %>
        <li>
          <.icon :if={i > 0} name="hero-chevron-right-micro" class="breadcrumb-separator" />
          <%= if i < length(@item) - 1 do %>
            <a href="#">{render_slot(item)}</a>
          <% else %>
            <span aria-current="page">{render_slot(item)}</span>
          <% end %>
        </li>
      <% end %>
    </ol>
    """
  end

  attr :mode, :string, required: true
  attr :page, :string, required: true
  attr :team, :string, default: nil
  attr :email, :string, default: nil

  defp page(%{page: "activity"} = assigns) do
    assigns =
      assign(assigns,
        attendance: [
          %{id: 1, name: "Alex Morgan", hours: "6 hours"},
          %{id: 2, name: "Blake Chen", hours: "6 hours"},
          %{id: 3, name: "Casey Singh", hours: "4h 30m"},
          %{id: 4, name: "Dana Okafor", hours: "4h 30m"}
        ]
      )

    ~H"""
    <.crumbs>
      <:item>Activities</:item>
      <:item>A-0412</:item>
    </.crumbs>
    <h1 class="title">Lost hiker, Example Ridge</h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl>
          <dt>Kind</dt>
          <dd>
            <.badge kind={:incident}>Incident</.badge>
          </dd>
          <dt>Attendance</dt>
          <dd>4 members · 21 hours in total</dd>
          <dt>Start</dt>
          <dd>Sat Oct 10, 2026 14:05</dd>
          <dt>Duration</dt>
          <dd>6 hours</dd>
          <dt>Actions</dt>
          <dd>
            <ul class="action-list">
              <li>
                <.a href="#">Apply a template</.a>
              </li>
              <li>
                <.a href="#">Take attendance</.a>
              </li>
              <li>
                <.a href="#">Import attendance</.a>
              </li>
              <li>
                <.a href="#">Mileage report</.a>
              </li>
            </ul>
          </dd>
        </dl>
      </aside>
      <main class="content-2/3">
        <h2 class="heading">Attendance · 4</h2>
        <.table id="mock-attendance" rows={@attendance} row_id={&"a-#{&1.id}"} class="table-striped">
          <:col :let={row} label="Member">
            <.a href="#">{row.name}</.a>
          </:col>
          <:col :let={row} label="Hours" align="right" class="w-px whitespace-nowrap">
            {row.hours}
          </:col>
        </.table>
      </main>
    </div>
    """
  end

  defp page(%{page: "member"} = assigns) do
    assigns =
      assign(assigns,
        rows: [
          %{id: 1, title: "Lost hiker, Example Ridge", date: "Oct 10, 2026", hours: "6 hours"},
          %{id: 2, title: "Rope rescue training", date: "Oct 3, 2026", hours: "3 hours"},
          %{id: 3, title: "Swiftwater exercise", date: "Sep 26, 2026", hours: "4 hours"}
        ]
      )

    ~H"""
    <.crumbs>
      <:item>Members</:item>
      <:item>Blake Chen</:item>
    </.crumbs>
    <h1 class="title">Blake Chen</h1>
    <%!-- The record's tabs sit under its title, above both columns, so they keep their
    width beside the sidebar. --%>
    <nav class="tabs" aria-label="Member">
      <a href="#" aria-current="page">Attendance</a>
      <a href="#">Qualifications</a>
      <a href="#">Groups</a>
      <a href="#">ID card</a>
      <a href="#">History</a>
    </nav>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl>
          <dt>Member number</dt>
          <dd>102</dd>
          <dt>Status</dt>
          <dd>Operational</dd>
          <dt>Joined</dt>
          <dd>Jan 1, 2020</dd>
        </dl>
      </aside>
      <main class="content-2/3">
        <.table id="mock-member" rows={@rows} row_id={&"m-#{&1.id}"} class="table-striped">
          <:col :let={row} label="Activity">
            <.a href="#">{row.title}</.a>
          </:col>
          <:col :let={row} label="Date" class="w-px whitespace-nowrap">{row.date}</:col>
          <:col :let={row} label="Hours" align="right" class="w-px whitespace-nowrap">
            {row.hours}
          </:col>
        </.table>
      </main>
    </div>
    """
  end

  defp page(%{page: "logins"} = assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">Member logins</h1>
      <p class="lead">
        Let your members log in to get their own ID card and tax credit letters.
      </p>
      <p>
        Each member sees only their own ID card and letters. They log in with the email or
        mobile number D4H has for them.
      </p>
      <p class="mb-6">Members who have left or retired cannot log in.</p>
      <form id="mock-logins-form">
        <.input
          id="mock-logins"
          name="member_logins"
          type="checkbox"
          value="true"
          label="Let members log in"
        />
        <.form_actions>
          <.button variant={:success}>Save settings</.button>
        </.form_actions>
      </form>
    </div>
    """
  end

  defp page(%{page: "templates"} = assigns) do
    assigns =
      assign(assigns,
        rows: [
          %{id: 1, title: "Boat training", items: 3, tags: 2, groups: 1},
          %{id: 2, title: "Managers' training", items: 1, tags: 1, groups: 1},
          %{id: 3, title: "Truck 2", items: 2, tags: 0, groups: 0}
        ]
      )

    ~H"""
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

  defp page(%{page: "overview"} = assigns) do
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
      <h2 class="heading mt-8">Hours in 2026</h2>
      <p>212 hours.</p>
    </div>
    """
  end

  defp page(%{page: "details"} = assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">Your contact details</h1>
      <p class="lead">Saving changes them in D4H, where your team admins see them.</p>
      <form id="mock-details-form">
        <.input
          id="mock-address"
          name="address"
          type="textarea"
          rows="4"
          value=""
          label="Mailing address"
        />
        <h2 class="heading mt-8">Emergency contact</h2>
        <.input id="mock-ec-name" name="ec_name" value="" label="Name" />
        <.input id="mock-ec-phone" name="ec_phone" value="" label="Phone" />
        <.form_actions>
          <.button variant={:success}>Save details</.button>
        </.form_actions>
      </form>
    </div>
    """
  end

  defp page(%{page: "teams"} = assigns) do
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

  defp page(%{page: "account"} = assigns) do
    ~H"""
    <h1 class="title">Account</h1>
    <p>Logged in as {@email}. Your email and your teams come from D4H.</p>
    <form id="mock-maps-form" class="mt-8">
      <fieldset>
        <legend class="heading">Maps app</legend>
        <p class="hint">Places in SAR Duty open in this app.</p>
        <label class="choice">
          <input type="radio" name="maps_app" value="google" checked /> Google Maps
        </label>
        <label class="choice"><input type="radio" name="maps_app" value="apple" /> Apple Maps</label>
      </fieldset>
    </form>
    """
  end

  defp css do
    """
    .mock-note { position: fixed; bottom: var(--sp-2); right: var(--sp-2); z-index: 50; padding: var(--sp-1) var(--sp-2); background: var(--warning); color: var(--on-warning); font-size: var(--fs-xs); border-radius: var(--radius); }
    .mock-body { padding-top: var(--sp-16); }
    .menu .mock-menu-team { padding: var(--sp-2) var(--sp-4) 0; font-weight: 700; color: var(--text); font-size: var(--fs-xs); line-height: var(--lh-xs); }
    .menu .mock-menu-visit { padding-top: 0; padding-bottom: 0; }
    .site-bar-phone-panel .mock-menu-team { padding: var(--sp-2) var(--sp-4) 0; font-weight: 700; color: #fff; font-size: var(--fs-sm); line-height: var(--lh-sm); }
    .site-bar-phone-panel .mock-menu-visit { padding-top: 0; padding-bottom: 0; }

    .mock-mode { display: inline-flex; align-items: baseline; gap: var(--sp-2); color: #fff; font-weight: 600; font-size: var(--fs-md); line-height: var(--lh-md); white-space: nowrap; padding: var(--sp-3) var(--sp-2); text-decoration: none; }
    .mock-mode:hover { text-decoration: underline; }
    .mock-mode-kind { color: #d5dbe3; font-weight: 400; font-size: var(--fs-sm); line-height: var(--lh-sm); }
    .mock-mode-phone { display: none; min-width: 0; flex-direction: column; color: #fff; text-decoration: none; }
    .mock-mode-phone > :first-child { font-weight: 600; font-size: var(--fs-sm); line-height: var(--lh-sm); }
    .mock-mode-phone-kind { color: #d5dbe3; font-size: var(--fs-xs); line-height: var(--lh-xs); }
    @media (width < 64rem) { .mock-mode-phone { display: flex; } }

    .mock-with-sidebar { display: flex; gap: var(--sp-8); }
    .mock-main { flex: 1; min-width: 0; }
    .mock-sidebar { width: 200px; flex-shrink: 0; position: sticky; top: calc(var(--sp-16) + var(--sp-2)); align-self: flex-start; max-height: calc(100dvh - var(--sp-16) - var(--sp-4)); overflow-y: auto; font-size: var(--fs-sm); line-height: var(--lh-sm); }
    .mock-sidebar-group { padding: var(--sp-2) 0; border-bottom: 1px solid var(--border-subtle); }
    .mock-sidebar-group:first-child { padding-top: 0; }
    .mock-sidebar-group:last-child { border-bottom: 0; }
    .mock-sidebar-heading { padding: var(--sp-1) var(--sp-3); }
    .mock-sidebar a { display: block; padding: var(--sp-2) var(--sp-3); color: var(--text); text-decoration: none; border-radius: var(--radius); }
    .mock-sidebar a:hover { background: var(--row-hover); }
    .mock-sidebar a[aria-current="page"] { font-weight: 700; box-shadow: inset 4px 0 var(--primary); }
    .mock-link-row { display: flex; align-items: center; justify-content: space-between; gap: var(--sp-2); }
    @media (width < 64rem) { .mock-sidebar { display: none; } }
    """
  end
end
