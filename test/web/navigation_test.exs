defmodule Web.NavigationTest do
  use ExUnit.Case, async: true

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.Team
  alias Web.Navigation

  @team %Team{id: 1, name: "Squamish SAR", subdomain: "squamish"}
  @pemberton %Team{id: 2, name: "Pemberton SAR", subdomain: "pemberton"}

  defp keys(sections), do: Enum.map(sections, fn links -> Enum.map(links, & &1.key) end)
  defp current(sections), do: for(links <- sections, link <- links, link.current, do: link.key)

  defp team_sections(path, opts, team \\ @team),
    do: path |> Navigation.area(team) |> Navigation.sections(path, opts)

  describe "area/2" do
    test "a team's pages are its space, when the URL's team is the current team" do
      assert %{kind: :team, name: "Squamish SAR", team: @team} =
               Navigation.area("/teams/squamish/activities/7", @team)

      assert %{kind: :team} = Navigation.area("/teams/squamish/me", @team)
      assert Navigation.area("/teams/pemberton", @team) == nil
    end

    test "SAR Duty admin, account settings, and nothing elsewhere" do
      assert %{kind: :admin, name: "SAR Duty admin"} = Navigation.area("/admin/orgs/3", nil)
      assert %{kind: :settings, name: "Account settings"} = Navigation.area("/account", @team)
      assert Navigation.area("/", @team) == nil
      assert Navigation.area("/administrators", @team) == nil
      assert Navigation.area(nil, @team) == nil
    end
  end

  describe "home_path/4" do
    test "logged out, the logo goes to the home page" do
      assert Navigation.home_path(nil, nil, nil, []) == "/"
    end

    test "on a team, the logo goes to its Dashboard" do
      user = %User{is_admin: true}
      area = Navigation.area("/teams/squamish/members", @team)
      assert Navigation.home_path(user, area, @team, []) == "/teams/squamish"
    end

    test "elsewhere, the team logging in lands on, then a member's team, then admin" do
      user = %User{is_admin: false}
      member = %Member{team: @pemberton}

      assert Navigation.home_path(user, nil, @team, [member]) == "/teams/squamish"
      assert Navigation.home_path(user, nil, nil, [member]) == "/teams/pemberton"
      assert Navigation.home_path(%User{is_admin: true}, %{kind: :admin}, nil, []) == "/admin"
      assert Navigation.home_path(user, nil, nil, []) == "/"
    end
  end

  describe "sections/3" do
    test "a member sees Dashboard, Activities, and Your membership, each its own section" do
      sections = team_sections("/teams/squamish/me", member?: true, proposed_changes: 2)
      assert keys(sections) == [["dashboard"], ["activities"], ["me"]]
      assert [_dashboard, [%{count: nil}] | _rest] = sections

      assert [
               _dashboard,
               _activities,
               [%{label: "Your membership", path: "/teams/squamish/me", current: true}]
             ] = sections
    end

    test "a team admin who is a member sees all seven sections" do
      assert "/teams/squamish" |> team_sections(team_admin?: true, member?: true) |> keys() ==
               [
                 ["dashboard"],
                 ["activities", "templates"],
                 ["members", "groups", "qualifications", "endorsements"],
                 ["equipment"],
                 ["tax-credit-letters"],
                 ["settings"],
                 ["me"]
               ]
    end

    test "a SAR Duty admin on a team they don't belong to sees sections 1 to 6" do
      sections = team_sections("/teams/squamish", team_admin?: true)
      assert length(sections) == 6
      refute "me" in (sections |> keys() |> List.flatten())
    end

    test "someone who is neither sees nothing" do
      assert team_sections("/teams/squamish", []) == []
    end

    test "Proposed changes shows with MCP on or when something waits, with the count" do
      activity_keys = fn sections -> sections |> Enum.at(1) |> Enum.map(& &1.key) end

      sections = team_sections("/teams/squamish", team_admin?: true)
      assert activity_keys.(sections) == ["activities", "templates"]

      [_dashboard, [_activities, _templates, proposed] | _rest] =
        team_sections("/teams/squamish/proposed-changes/3",
          team_admin?: true,
          proposed_changes: 2
        )

      assert %{key: "proposed-changes", count: 2, current: true} = proposed

      mcp_team = %{@team | mcp_enabled: true}

      [_dashboard, [_activities, _templates, proposed] | _rest] =
        "/teams/squamish" |> team_sections([team_admin?: true], mcp_team)

      assert proposed.count == nil
    end

    test "the first page is current only on itself; others on anything under them" do
      opts = [team_admin?: true, member?: true]
      assert current(team_sections("/teams/squamish", opts)) == ["dashboard"]
      assert current(team_sections("/teams/squamish/activities/7/tags", opts)) == ["activities"]
      assert current(team_sections("/teams/squamish/templates/3", opts)) == ["templates"]
      assert current(team_sections("/teams/squamish/settings/managers", opts)) == ["settings"]
      assert current(team_sections("/teams/squamish/me/details", opts)) == ["me"]
      assert current(team_sections("/teams/squamish/members-x", opts)) == []
    end

    test "SAR Duty admin has three sections; account settings and pages outside an area none" do
      sections = "/admin/orgs" |> Navigation.area(nil) |> Navigation.sections("/admin/orgs")
      assert sections |> keys() |> List.last() == ["admin-styles"]
      assert length(sections) == 3
      assert current(sections) == ["admin-orgs"]

      assert "/account" |> Navigation.area(nil) |> Navigation.sections("/account") == []
      assert Navigation.sections(nil, "/") == []
    end
  end

  describe "switch_rows/4" do
    defp rows(rows), do: for(row <- rows, do: {row.label, row.current})

    test "SAR Duty admin first, then each team once, A to Z, the current one marked" do
      area = Navigation.area("/teams/squamish", @team)

      rows =
        Navigation.switch_rows(
          true,
          [@team],
          [%Member{team: @team}, %Member{team: @pemberton}],
          area
        )

      assert rows(rows) == [
               {"SAR Duty admin", false},
               {"Pemberton SAR", false},
               {"Squamish SAR", true}
             ]

      assert Enum.map(rows, & &1.path) == ["/admin", "/teams/pemberton", "/teams/squamish"]
    end

    test "one place is nothing to switch to, so the name is plain text" do
      area = Navigation.area("/teams/squamish/me", @team)
      assert Navigation.switch_rows(false, [], [%Member{team: @team}], area) == []
      assert Navigation.switch_rows(true, [], [], Navigation.area("/admin", nil)) == []
    end

    test "a team opened from Admin that isn't yours marks nothing" do
      area = Navigation.area("/teams/pemberton", @pemberton)
      rows = Navigation.switch_rows(true, [], [], area)
      assert rows(rows) == [{"SAR Duty admin", false}]
    end
  end

  describe "person/3" do
    test "the member's name and its initials" do
      user = %User{email: "sam@example.com"}

      assert Navigation.person(user, %Member{name: "Sam Rivera Jones"}, []) == %{
               name: "Sam Rivera Jones",
               email: "sam@example.com",
               initials: "SJ"
             }

      assert %{name: "Sam Rivera"} =
               Navigation.person(user, nil, [%Member{name: "Sam Rivera", team: @team}])
    end

    test "with no member anywhere, the initials come from the email" do
      assert %{name: nil, initials: "GS"} =
               Navigation.person(%User{email: "gerry_shaw@example.com"}, nil, [])

      assert %{initials: "A"} = Navigation.person(%User{email: "avery@example.com"}, nil, [])
    end
  end
end
