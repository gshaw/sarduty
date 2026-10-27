defmodule Web.NavigationTest do
  use ExUnit.Case, async: true

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.Organization
  alias App.Model.Team
  alias Web.Navigation

  @team %Team{id: 1, name: "Squamish SAR", subdomain: "squamish"}
  @pemberton %Team{id: 2, name: "Pemberton SAR", subdomain: "pemberton"}
  @wsara %Organization{id: 5, name: "Western SAR Association", short_name: "WSARA", slug: "wsara"}
  @nsara %Organization{
    id: 6,
    name: "Northern SAR Association",
    short_name: "NSARA",
    slug: "nsara"
  }

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

  describe "outside_area/3" do
    test "logged out, the bar names nothing" do
      assert Navigation.outside_area(nil, @team, []) == nil
    end

    test "the team logging in lands on, then a member's team, then admin" do
      user = %User{is_admin: false}
      member = %Member{team: @pemberton}

      assert Navigation.outside_area(user, @team, [member]) ==
               %{kind: :team, name: "Squamish SAR", team: @team}

      assert Navigation.outside_area(user, nil, [member]).team == @pemberton
      assert %{kind: :admin} = Navigation.outside_area(%User{is_admin: true}, nil, [])
      assert Navigation.outside_area(user, nil, []) == nil
    end
  end

  describe "sections/3" do
    test "a member sees Dashboard, Activities and Take attendance, Members and Milestones, and Your membership" do
      sections = team_sections("/teams/squamish/me", member?: true, chores: 2)

      assert keys(sections) == [
               ["dashboard", "whiteboard"],
               ["activities", "take-attendance"],
               ["members", "milestones"],
               ["me"]
             ]

      assert [_dashboard, [%{count: nil}, _take_attendance] | _rest] = sections

      assert [
               _dashboard,
               _activities,
               _people,
               [%{label: "Your membership", path: "/teams/squamish/me", current: true}]
             ] = sections
    end

    test "a team admin who is a member sees all six sections" do
      assert "/teams/squamish" |> team_sections(team_admin?: true, member?: true) |> keys() ==
               [
                 ["dashboard", "whiteboard"],
                 ["activities", "take-attendance", "templates"],
                 [
                   "members",
                   "milestones",
                   "groups",
                   "qualifications",
                   "endorsements",
                   "tax-credit-letters"
                 ],
                 ["equipment"],
                 ["settings"],
                 ["me"]
               ]
    end

    test "a SAR Duty admin on a team they don't belong to sees sections 1 to 5" do
      sections = team_sections("/teams/squamish", team_admin?: true)
      assert length(sections) == 5
      refute "me" in (sections |> keys() |> List.flatten())
    end

    test "chores show a team admin with member logins and chores on, with a count while some wait" do
      refute "chores" in ("/teams/squamish"
                          |> team_sections([team_admin?: true, chores: 3], %{
                            @team
                            | member_logins: true
                          })
                          |> keys()
                          |> List.flatten())

      team = %{@team | member_logins: true, chores_enabled: true}
      sections = team_sections("/teams/squamish", [team_admin?: true, chores: 3], team)
      assert [%{count: 3}] = for(links <- sections, link <- links, link.key == "chores", do: link)
      assert ["equipment", "chores"] in keys(sections)

      refute "chores" in ("/teams/squamish"
                          |> team_sections([member?: true], team)
                          |> keys()
                          |> List.flatten())
    end

    test "Whiteboard follows Dashboard while the team has the module on" do
      assert [["dashboard", "whiteboard"] | _rest] =
               "/teams/squamish/whiteboard" |> team_sections(member?: true) |> keys()

      assert "/teams/squamish/whiteboard" |> team_sections(member?: true) |> current() ==
               ["whiteboard"]

      team = %{@team | whiteboard_enabled: false}

      assert [["dashboard"] | _rest] =
               "/teams/squamish" |> team_sections([team_admin?: true], team) |> keys()
    end

    test "someone who is neither sees nothing" do
      assert team_sections("/teams/squamish", []) == []
    end

    test "activities' section is Activities, Take attendance, and Templates" do
      activity_keys = fn sections -> sections |> Enum.at(1) |> Enum.map(& &1.key) end

      sections = team_sections("/teams/squamish", team_admin?: true)
      assert activity_keys.(sections) == ["activities", "take-attendance", "templates"]
    end

    test "the first page is current only on itself; others on anything under them" do
      opts = [team_admin?: true, member?: true]
      assert current(team_sections("/teams/squamish", opts)) == ["dashboard"]
      assert current(team_sections("/teams/squamish/activities/7/tags", opts)) == ["activities"]
      assert current(team_sections("/teams/squamish/templates/3", opts)) == ["templates"]

      assert current(team_sections("/teams/squamish/take-attendance", opts)) == [
               "take-attendance"
             ]

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

    test "each team once, A to Z, then SAR Duty admin, the current one marked" do
      area = Navigation.area("/teams/squamish", @team)

      rows =
        Navigation.switch_rows(
          true,
          [@team],
          [%Member{team: @team}, %Member{team: @pemberton}],
          area
        )

      assert rows(rows) == [
               {"Pemberton SAR", false},
               {"Squamish SAR", true},
               {"SAR Duty admin", false}
             ]

      assert Enum.map(rows, & &1.path) == ["/teams/pemberton", "/teams/squamish", "/admin"]
      assert Enum.map(rows, & &1.kind) == [:team, :team, :admin]
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

  describe "an organization's space (#512)" do
    test "its pages are its area, when the URL's organization is the current one" do
      assert %{kind: :org, name: "Western SAR Association", short_name: "WSARA", team: nil} =
               Navigation.area("/orgs/wsara/settings/admins", nil, @wsara)

      assert Navigation.area("/orgs/nsara", nil, @wsara) == nil
      assert Navigation.area("/orgs/wsara", @team, nil) == nil
    end

    test "its sections are Teams, then Organization settings" do
      path = "/orgs/wsara/settings/hours-tags"
      sections = path |> Navigation.area(nil, @wsara) |> Navigation.sections(path)

      assert keys(sections) == [["org-teams"], ["org-settings"]]
      assert current(sections) == ["org-settings"]

      teams = "/orgs/wsara" |> Navigation.area(nil, @wsara) |> Navigation.sections("/orgs/wsara")
      assert current(teams) == ["org-teams"]
    end

    test "the switcher lists your organizations after your teams, before SAR Duty admin" do
      area = Navigation.area("/orgs/wsara", nil, @wsara)
      rows = Navigation.switch_rows(true, [@team], [], [@wsara, @nsara], area)

      assert Enum.map(rows, &{&1.kind, &1.key, &1.current}) == [
               {:team, "team-squamish", false},
               {:org, "org-nsara", false},
               {:org, "org-wsara", true},
               {:admin, "admin", false}
             ]
    end

    test "an organization admin with no team sees no switcher in their one organization" do
      area = Navigation.area("/orgs/wsara", nil, @wsara)
      assert Navigation.switch_rows(false, [], [], [@wsara], area) == []
    end

    test "outside every area, the bar names their first organization after member teams" do
      user = %User{is_admin: true}

      assert %{kind: :org, organization: @wsara} =
               Navigation.outside_area(user, nil, [], [@wsara, @nsara])

      assert %{kind: :team, team: @team} =
               Navigation.outside_area(user, nil, [%Member{team: @team}], [@wsara])
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
