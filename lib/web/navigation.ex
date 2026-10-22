defmodule Web.Navigation do
  @moduledoc """
  Where a page sits, for the top bar and the side navigation (#312, #406). A page is in one
  area: a team's space, SAR Duty admin, or Account settings. The bar names the area, with
  the team switcher on it, and the side navigation lists the area's pages in sections. Who
  you are on the team decides which sections you see.

  Pure: the layout passes in what the page assigned. See docs/navigation.md.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: Web.Endpoint,
    router: Web.Router,
    statics: Web.static_paths()

  alias App.Model.Team

  @doc """
  The page's area, or nil outside one, from its path. A team's pages need the URL's team
  as `current_team`, as the team pages' hook assigns it.
  `%{kind: :team | :admin | :settings, name:, team:}`.
  """
  def area(path, current_team)

  def area(nil, _current_team), do: nil

  def area(path, current_team) do
    case String.split(path, "/", trim: true) do
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
  `%{key:, label:, path:, current:, count:}`; the one for `path` is current.

  On a team: `team_admin?` when you manage it, `member?` when you log in as one of its
  members, and `proposed_changes`, how many AI agent change sets wait for a team admin.
  """
  def sections(area, path, opts \\ [])

  def sections(%{kind: :team, team: team}, path, opts) do
    team_admin? = Keyword.get(opts, :team_admin?, false)
    member? = Keyword.get(opts, :member?, false)
    proposed_changes = Keyword.get(opts, :proposed_changes, 0)

    team_sections =
      cond do
        team_admin? -> team_admin_sections(team, proposed_changes)
        member? -> [[dashboard_link(team)], [activities_link(team)]]
        true -> []
      end

    member_sections =
      if member?, do: [[link("me", "Your membership", ~p"/teams/#{team}/me")]], else: []

    mark_current(team_sections ++ member_sections, path)
  end

  def sections(%{kind: :admin}, path, _opts) do
    mark_current(
      [
        [
          link("admin-teams", "Teams", ~p"/admin", exact: true),
          link("admin-orgs", "Organizations", ~p"/admin/orgs"),
          link("admin-id-cards", "ID cards", ~p"/admin/id-cards")
        ],
        [
          link("admin-admins", "Admins", ~p"/admin/admins"),
          link("admin-events", "Events", ~p"/admin/events"),
          link("admin-mcp", "MCP", ~p"/admin/mcp")
        ],
        [link("admin-styles", "Style guide", "/styles")]
      ],
      path
    )
  end

  def sections(_area, _path, _opts), do: []

  defp team_admin_sections(team, proposed_changes) do
    [
      [dashboard_link(team)],
      activity_links(team, proposed_changes),
      people_links(team),
      [link("equipment", "Equipment", ~p"/teams/#{team}/equipment")],
      [link("tax-credit-letters", "Tax credit letters", ~p"/teams/#{team}/tax-credit-letters")],
      [link("settings", "Team settings", ~p"/teams/#{team}/settings")]
    ]
  end

  # Activities' pages for team admins, each its own link so Templates is easy to find.
  # Proposed changes come from AI agents through MCP, a trial most teams don't have: the
  # link shows only when the team has it, or something waits there, with the count.
  defp activity_links(team, proposed_changes) do
    proposed =
      link("proposed-changes", "Proposed changes", ~p"/teams/#{team}/proposed-changes",
        count: proposed_changes
      )

    [
      activities_link(team),
      link("templates", "Templates", ~p"/teams/#{team}/templates")
    ] ++ if(team.mcp_enabled or proposed_changes > 0, do: [proposed], else: [])
  end

  defp dashboard_link(team), do: link("dashboard", "Dashboard", ~p"/teams/#{team}", exact: true)
  defp activities_link(team), do: link("activities", "Activities", ~p"/teams/#{team}/activities")

  defp people_links(team) do
    [
      link("members", "Members", ~p"/teams/#{team}/members"),
      link("groups", "Groups", ~p"/teams/#{team}/groups"),
      link("qualifications", "Qualifications", ~p"/teams/#{team}/qualifications"),
      link("endorsements", "Endorsements", ~p"/teams/#{team}/endorsements")
    ]
  end

  defp link(key, label, path, opts \\ []) do
    count = opts[:count]

    %{
      key: key,
      label: label,
      path: path,
      exact: Keyword.get(opts, :exact, false),
      count: if(count && count > 0, do: count),
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

  defp current?(%{path: path}, current),
    do: current == path or String.starts_with?(current, path <> "/")

  @doc """
  Where the logo goes. Logged in, it's your team rather than the public home page: the
  team you're on, else the one logging in lands on (the last you opened, or your first),
  else the team you log in to as a member, else SAR Duty admin for an admin. Pass the
  `current_team` the page assigned.
  """
  def home_path(user, area, current_team, member_logins)

  def home_path(nil, _area, _current_team, _member_logins), do: ~p"/"
  def home_path(_user, %{kind: :team, team: team}, _current_team, _logins), do: ~p"/teams/#{team}"

  def home_path(user, _area, current_team, member_logins) do
    cond do
      current_team -> ~p"/teams/#{current_team}"
      member = List.first(member_logins) -> ~p"/teams/#{member.team}"
      user.is_admin -> ~p"/admin"
      true -> ~p"/"
    end
  end

  @doc """
  The team switcher's rows: "SAR Duty admin" first for SAR Duty admins, then each team
  where you're a team admin or a member, A to Z, one row per team. The area you're in is
  current; a team opened from Admin › Teams that isn't yours marks nothing. Empty when
  there is nowhere else to go, so the bar's name is plain text.
  `[%{key:, label:, path:, current:}]`.
  """
  def switch_rows(is_admin, managed_teams, member_logins, area) do
    admin =
      if is_admin,
        do: [
          %{
            key: "admin",
            label: "SAR Duty admin",
            path: ~p"/admin",
            current: match?(%{kind: :admin}, area)
          }
        ],
        else: []

    teams =
      for team <- teams(managed_teams, member_logins) do
        %{
          key: "team-" <> team.subdomain,
          label: team.name,
          path: ~p"/teams/#{team}",
          current: match?(%{kind: :team, team: %{id: id}} when id == team.id, area)
        }
      end

    rows = admin ++ teams
    if Enum.all?(rows, & &1.current), do: [], else: rows
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
