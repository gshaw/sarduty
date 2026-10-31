defmodule Web.Navigation do
  @moduledoc """
  Where a page sits, for the top bar and the side navigation (#312, #406). A page is in one
  area: a team's space, an organization's space (#512), SAR Duty admin, or Account
  settings. The bar names the area, with the team switcher on it, and the side navigation
  lists the area's pages in sections. Who you are on the team decides which sections you
  see.

  Pure: the layout passes in what the page assigned. See docs/navigation.md.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: Web.Endpoint,
    router: Web.Router,
    statics: Web.static_paths()

  alias App.Model.Organization
  alias App.Model.Team

  @doc """
  The page's area, or nil outside one, from its path. A team's pages need the URL's team
  as `current_team`, as the team pages' hook assigns it, and an organization's pages its
  `current_organization`. `%{kind: :team | :org | :admin | :settings, name:, team:}`; an
  organization's also has `organization:` and the `short_name` the phone bar shows.
  """
  def area(path, current_team, current_organization \\ nil)

  def area(nil, _current_team, _current_organization), do: nil

  def area(path, current_team, current_organization) do
    case String.split(path, "/", trim: true) do
      ["orgs", slug | _rest] ->
        if match?(%Organization{slug: ^slug}, current_organization),
          do: org_area(current_organization)

      ["admin" | _rest] ->
        %{kind: :admin, name: "SAR Duty admin", team: nil}

      ["account"] ->
        %{kind: :settings, name: "Account settings", team: nil}

      ["teams", subdomain | _rest] ->
        if match?(%Team{subdomain: ^subdomain}, current_team),
          do: %{kind: :team, name: current_team.name, team: current_team}

      _other ->
        nil
    end
  end

  @doc """
  The area's pages in sections, each a list of links, split by a divider and never
  headed. A section with nothing you can see is left out. Each link is
  `%{key:, label:, path:, current:}`; the one for `path` is current.

  On a team: `team_admin?` when you manage it, and `member?` when you log in as one of
  its members. No link has a count: what waits for a team admin is on the Dashboard's
  Needs attention, which leaves out their own (#698).
  """
  def sections(area, path, opts \\ [])

  def sections(%{kind: :team, team: team}, path, opts) do
    team_admin? = Keyword.get(opts, :team_admin?, false)
    member? = Keyword.get(opts, :member?, false)

    team_sections =
      cond do
        team_admin? ->
          team_admin_sections(team)

        member? ->
          [
            dashboard_links(team),
            [activities_link(team), take_attendance_link(team)],
            member_links(team),
            chore_links(team)
          ]

        true ->
          []
      end

    member_sections = if member?, do: [[me_link(team, team_admin?)]], else: []

    (team_sections ++ member_sections)
    |> Enum.reject(&(&1 == []))
    |> mark_current(path)
  end

  def sections(%{kind: :org, organization: organization}, path, _opts) do
    mark_current(
      [
        [link("org-teams", "Teams", ~p"/orgs/#{organization}", exact: true)],
        [link("org-settings", "Organization settings", ~p"/orgs/#{organization}/settings")]
      ],
      path
    )
  end

  def sections(%{kind: :admin}, path, _opts) do
    mark_current(
      [
        [
          link("admin-teams", "Teams", ~p"/admin", exact: true),
          link("admin-orgs", "Organizations", ~p"/admin/orgs")
        ],
        [
          link("admin-admins", "Admins", ~p"/admin/admins"),
          link("admin-events", "Events", ~p"/admin/events"),
          link("admin-mcp", "MCP calls", ~p"/admin/mcp")
        ]
      ],
      path
    )
  end

  def sections(_area, _path, _opts), do: []

  defp team_admin_sections(team) do
    [
      dashboard_links(team),
      activity_links(team),
      people_links(team),
      [link("equipment", "Equipment", ~p"/teams/#{team}/equipment") | chore_links(team)],
      [link("settings", "Team settings", ~p"/teams/#{team}/settings")]
    ]
  end

  # Activities' pages for team admins, each its own link so Templates is easy to find.
  defp activity_links(team) do
    [
      activities_link(team),
      take_attendance_link(team),
      link("templates", "Templates", ~p"/teams/#{team}/templates")
    ]
  end

  # The Whiteboard page is where notes are posted and read in full (#515); the Dashboard
  # shows a line or 2 of them.
  defp dashboard_links(team) do
    [link("dashboard", "Dashboard", ~p"/teams/#{team}", exact: true)] ++
      if(Team.whiteboard?(team),
        do: [link("whiteboard", "Whiteboard", ~p"/teams/#{team}/whiteboard")],
        else: []
      )
  end

  defp activities_link(team), do: link("activities", "Activities", ~p"/teams/#{team}/activities")

  # Always there, not only while an activity is on: links that come and go with the clock
  # make the menu harder to learn (#475).
  defp take_attendance_link(team),
    do: link("take-attendance", "Take attendance", ~p"/teams/#{team}/take-attendance")

  # Chores is one page for everyone (#645): members log theirs there, and team admins
  # accept them. It shows with member logins and chores on. For team admins it shares
  # Equipment's section: chores are mostly equipment upkeep, and a section of one link
  # looked lost.
  defp chore_links(team) do
    if Team.chores?(team),
      do: [link("chores", "Chores", ~p"/teams/#{team}/chores")],
      else: []
  end

  # Certificates follow Qualifications on a team where members send them (#493).
  defp people_links(team) do
    member_links(team) ++
      [
        link("groups", "Groups", ~p"/teams/#{team}/groups"),
        link("qualifications", "Qualifications", ~p"/teams/#{team}/qualifications")
      ] ++
      certificate_links(team) ++
      [
        link("endorsements", "Endorsements", ~p"/teams/#{team}/endorsements"),
        link("tax-credit-letters", "Tax credit letters", ~p"/teams/#{team}/tax-credit-letters")
      ]
  end

  # The people pages members open too (#440).
  defp member_links(team) do
    [
      link("members", "Members", ~p"/teams/#{team}/members"),
      link("milestones", "Milestones", ~p"/teams/#{team}/milestones")
    ]
  end

  defp certificate_links(team) do
    if Team.certificates?(team),
      do: [link("certificates", "Certificates", ~p"/teams/#{team}/certificates")],
      else: []
  end

  # Your membership. A member's certificate form is under /certificates (#645), a page
  # members have no link to, so for them Your membership is current there too, as its
  # breadcrumbs say.
  defp me_link(team, true), do: link("me", "Your membership", ~p"/teams/#{team}/me")

  defp me_link(team, false),
    do:
      link("me", "Your membership", ~p"/teams/#{team}/me",
        also: [~p"/teams/#{team}/certificates"]
      )

  defp link(key, label, path, opts \\ []) do
    %{
      key: key,
      label: label,
      path: path,
      also: Keyword.get(opts, :also, []),
      exact: Keyword.get(opts, :exact, false),
      current: false
    }
  end

  # An area's first page is current only on itself, since every page is under it; other
  # links are current on any page under them.
  defp mark_current(sections, path) do
    for links <- sections do
      Enum.map(links, &%{&1 | current: current?(&1, path)})
    end
  end

  defp current?(_link, nil), do: false
  defp current?(%{exact: true, path: path}, current), do: current == path

  defp current?(%{path: path, also: also}, current),
    do: Enum.any?([path | also], &(current == &1 or String.starts_with?(current, &1 <> "/")))

  @doc """
  The area the bar names on a page outside every area (home, terms, privacy) when logged
  in, so it looks as it does everywhere else: the team logging in lands on (the last you
  opened, or your first), else the team you log in to as a member, else your first
  organization, else SAR Duty admin for an admin; nil otherwise. Only for the bar's name:
  the page stays outside, so the switcher marks nothing. Pass the `current_team` the page
  assigned.
  """
  def outside_area(user, current_team, member_logins, organizations \\ [])

  def outside_area(nil, _current_team, _member_logins, _organizations), do: nil

  def outside_area(user, current_team, member_logins, organizations) do
    cond do
      current_team -> team_area(current_team)
      member = List.first(member_logins) -> team_area(member.team)
      organization = List.first(organizations) -> org_area(organization)
      user.is_admin -> %{kind: :admin, name: "SAR Duty admin", team: nil}
      true -> nil
    end
  end

  @doc """
  Whether the person logged in opens `team`'s pages: a SAR Duty admin, one of its team
  admins, or a member who logs in there. Takes the assigns every page's hook sets. A
  reminder's link (#444) names its team in the bar when they do, not the team they last
  opened.
  """
  def opens_team?(%{current_user: nil}, _team), do: false

  def opens_team?(assigns, team) do
    assigns.current_user.is_admin or
      Enum.any?(assigns.managed_teams, &(&1.id == team.id)) or
      Enum.any?(assigns.member_logins, &(&1.team_id == team.id))
  end

  defp team_area(team), do: %{kind: :team, name: team.name, team: team}

  # `team: nil`, since the layout reads the area's team.
  defp org_area(organization),
    do: %{
      kind: :org,
      name: organization.name,
      short_name: organization.short_name,
      organization: organization,
      team: nil
    }

  @doc """
  The team switcher's rows: each team where you're a team admin or a member, A to Z, one
  row per team, then each organization you're an organization admin of (#512), then "SAR
  Duty admin" and "Style guide" last for SAR Duty admins, which the switcher sets apart. SAR Duty admins
  reach other organizations from Admin › Organizations. The area you're in is current; a
  team or organization opened as a SAR Duty admin that isn't yours marks nothing. Empty
  when there is nowhere else to go, so the bar's name is plain text.
  `[%{kind: :team | :org | :admin | :styles, key:, label:, path:, current:}]`.
  """
  def switch_rows(is_admin, managed_teams, member_logins, organizations \\ [], area) do
    teams = for team <- teams(managed_teams, member_logins), do: team_row(team, area)

    orgs =
      for organization <- Enum.sort_by(organizations, &String.downcase(&1.name)),
          do: org_row(organization, area)

    admin = if is_admin, do: [admin_row(area), styles_row()], else: []

    rows = teams ++ orgs ++ admin
    if Enum.all?(rows, &(&1.current or &1.kind == :styles)), do: [], else: rows
  end

  defp team_row(team, area) do
    %{
      kind: :team,
      key: "team-" <> team.subdomain,
      label: team.name,
      path: ~p"/teams/#{team}",
      current: match?(%{kind: :team, team: %{id: id}} when id == team.id, area)
    }
  end

  defp org_row(organization, area) do
    %{
      kind: :org,
      key: "org-" <> organization.slug,
      label: organization.name,
      path: ~p"/orgs/#{organization}",
      current: match?(%{kind: :org, organization: %{id: id}} when id == organization.id, area)
    }
  end

  defp admin_row(area) do
    %{
      kind: :admin,
      key: "admin",
      label: "SAR Duty admin",
      path: ~p"/admin",
      current: match?(%{kind: :admin}, area)
    }
  end

  # The style guide is no area, so it is never current.
  defp styles_row do
    %{kind: :styles, key: "styles", label: "Style guide", path: "/styles", current: false}
  end

  # Every team you manage or log in to as a member, once each, A to Z.
  defp teams(managed_teams, member_logins) do
    (managed_teams ++ Enum.map(member_logins, & &1.team))
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{String.downcase(&1.name), &1.id})
  end

  @doc """
  The person in the account menu: a name, when they log in as a member anywhere, their
  email, and initials for the avatar, from the name or else the email.
  `%{name:, email:, initials:}`.
  """
  def person(user, current_member, member_logins) do
    name =
      case current_member || List.first(member_logins) do
        %{name: name} when is_binary(name) and name != "" -> name
        _none -> nil
      end

    %{name: name, email: user.email, initials: initials(name || email_name(user.email))}
  end

  defp email_name(email), do: email |> String.split("@") |> List.first("")

  @doc ~s(An avatar's letters: "Sam Rivera Jones" is "SJ", "gerry_shaw" is "GS".)
  def initials(text) do
    words = String.split(text || "", ~r/[\s._+-]+/, trim: true)

    [List.first(words), if(length(words) > 1, do: List.last(words))]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end
end
