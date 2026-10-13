defmodule Web.Navigation do
  @moduledoc """
  Where a page sits, for the top bar and the side navigation (#312). A page is in one
  area: a team's (its team admins' pages), a member's (their own pages), admin, or your
  settings. The bar names the area, the side navigation lists the area's pages, and the
  account menu lists the areas you can switch to.

  Pure: the layout passes in what the page assigned. See docs/navigation.md.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: Web.Endpoint,
    router: Web.Router,
    statics: Web.static_paths()

  alias App.Model.Team

  @doc """
  The page's area, or nil outside one, from its path. A team's pages need the URL's team
  as `current_team`, and a member's pages the logged-in `member`, as the page's hooks
  assign them. `%{kind: :team | :member | :admin | :settings, name:, kind_label:, home:,
  team:}`.
  """
  def area(path, current_team, member)

  def area(nil, _current_team, _member), do: nil

  def area(path, current_team, member) do
    case String.split(path, "/", trim: true) do
      ["admin" | _rest] ->
        %{kind: :admin, name: "Admin", kind_label: nil, home: ~p"/admin", team: nil}

      ["account"] ->
        %{kind: :settings, name: "Your settings", kind_label: nil, home: ~p"/account", team: nil}

      ["teams", subdomain, "me" | _rest] ->
        if member && member.team.subdomain == subdomain, do: member_area(member.team)

      ["teams", subdomain | _rest] ->
        if match?(%Team{subdomain: ^subdomain}, current_team), do: team_area(current_team)

      _other ->
        nil
    end
  end

  defp team_area(team),
    do: %{
      kind: :team,
      name: team.name,
      kind_label: "Team area",
      home: ~p"/teams/#{team}",
      team: team
    }

  defp member_area(team) do
    %{
      kind: :member,
      name: team.name,
      kind_label: "Member area",
      home: ~p"/teams/#{team}/me",
      team: team
    }
  end

  @doc """
  The area's pages, as `{heading, links}` groups: a heading shows only over two or more
  links. Each link is `%{key:, label:, path:, current:, count:}`; the one for `path` is
  current. `proposed_changes` is how many AI agent change sets wait for a team admin.
  """
  def groups(area, path, proposed_changes \\ 0)

  def groups(%{kind: :team, team: team}, path, proposed_changes),
    do: team |> team_groups(proposed_changes) |> mark_current(path)

  def groups(%{kind: :member, team: team}, path, _proposed_changes),
    do: team |> member_groups() |> mark_current(path)

  def groups(%{kind: :admin}, path, _proposed_changes), do: mark_current(admin_groups(), path)
  def groups(_area, _path, _proposed_changes), do: []

  defp team_groups(team, proposed_changes) do
    [
      {nil, [link("dashboard", "Dashboard", ~p"/teams/#{team}", exact: true)]},
      {"Activities", activity_links(team, proposed_changes)},
      {"People",
       [
         link("members", "Members", ~p"/teams/#{team}/members"),
         link("qualifications", "Qualifications", ~p"/teams/#{team}/qualifications"),
         link("endorsements", "Endorsements", ~p"/teams/#{team}/endorsements"),
         link("groups", "Groups", ~p"/teams/#{team}/groups")
       ]},
      {nil, [link("equipment", "Equipment", ~p"/teams/#{team}/equipment")]},
      {nil,
       [link("tax-credit-letters", "Tax credit letters", ~p"/teams/#{team}/tax-credit-letters")]},
      {"Settings", settings_links(team)}
    ]
  end

  # Proposed changes come from AI agents through MCP, a trial most teams don't have: the
  # page shows only when the team has it, or something waits there.
  defp activity_links(team, proposed_changes) do
    proposed =
      link("proposed-changes", "Proposed changes", ~p"/teams/#{team}/proposed-changes",
        count: proposed_changes
      )

    [
      link("activities", "Activities", ~p"/teams/#{team}/activities"),
      link("templates", "Templates", ~p"/teams/#{team}/templates")
    ] ++ if(team.mcp_enabled or proposed_changes > 0, do: [proposed], else: [])
  end

  # MCP tokens show once a SAR Duty admin turns them on for the team. A team picks what
  # ID cards list on the endorsements page.
  defp settings_links(team) do
    Enum.filter(
      [
        link("settings", "General", ~p"/teams/#{team}/settings", exact: true),
        link("settings-managers", "Team admins", ~p"/teams/#{team}/settings/managers"),
        link(
          "settings-member-logins",
          "Member logins",
          ~p"/teams/#{team}/settings/member-logins"
        ),
        team.mcp_enabled && link("settings-mcp", "MCP tokens", ~p"/teams/#{team}/settings/mcp")
      ],
      & &1
    )
  end

  defp member_groups(team) do
    [
      {nil,
       [
         link("me", "Overview", ~p"/teams/#{team}/me", exact: true),
         link("me-details", "Contact details", ~p"/teams/#{team}/me/details"),
         link("me-mobile", "Mobile number", ~p"/teams/#{team}/me/mobile")
       ]}
    ]
  end

  defp admin_groups do
    [
      {nil,
       [
         link("admin-teams", "Teams", ~p"/admin", exact: true),
         link("admin-orgs", "Organizations", ~p"/admin/orgs"),
         link("admin-id-cards", "ID cards", ~p"/admin/id-cards")
       ]},
      {"SAR Duty",
       [
         link("admin-admins", "Admins", ~p"/admin/admins"),
         link("admin-events", "Events", ~p"/admin/events"),
         link("admin-mcp", "MCP", ~p"/admin/mcp")
       ]}
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
  # links are current on any page under them. A group of one link loses its heading.
  defp mark_current(groups, path) do
    for {heading, links} <- groups do
      {if(length(links) > 1, do: heading), Enum.map(links, &%{&1 | current: current?(&1, path)})}
    end
  end

  defp current?(_link, nil), do: false
  defp current?(%{exact: true, path: path}, current), do: current == path

  defp current?(%{path: path}, current),
    do: current == path or String.starts_with?(current, path <> "/")

  @doc """
  The teams in the account menu, A to Z, each with the areas it offers you: its team area
  when you're one of its team admins (`managed_teams`), its member area when you can log
  in as one of its members (`member_logins`). `[%{team:, team_area:, member_area:}]`.
  """
  def menu_teams(managed_teams, member_logins) do
    managed = Map.new(managed_teams, &{&1.id, &1})
    members = Map.new(member_logins, &{&1.team.id, &1.team})

    managed
    |> Map.merge(members)
    |> Map.values()
    |> Enum.sort_by(&{String.downcase(&1.name), &1.id})
    |> Enum.map(fn team ->
      %{
        team: team,
        team_area: Map.has_key?(managed, team.id),
        member_area: Map.has_key?(members, team.id)
      }
    end)
  end
end
