defmodule Web.NavigationTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.Team
  alias Web.Navigation

  @team %Team{id: 1, name: "Squamish SAR", subdomain: "squamish"}

  defp keys(groups), do: for({_heading, links} <- groups, link <- links, do: link.key)

  defp current(groups),
    do: for({_heading, links} <- groups, link <- links, link.current, do: link.key)

  describe "area/3" do
    test "a team's pages are its team area, when the URL's team is the current team" do
      area = Navigation.area("/teams/squamish/activities/7", @team, nil)

      assert %{
               kind: :team,
               name: "Squamish SAR",
               kind_label: "Team area",
               home: "/teams/squamish"
             } =
               area

      assert Navigation.area("/teams/pemberton", @team, nil) == nil
    end

    test "a member's own pages are their member area, from the member, not the current team" do
      member = %Member{team: @team}

      assert %{kind: :member, kind_label: "Member area"} =
               Navigation.area("/teams/squamish/me", nil, member)

      assert %{kind: :member} = Navigation.area("/teams/squamish/me/details", @team, member)
      assert Navigation.area("/teams/squamish/me", @team, nil) == nil
    end

    test "admin, your settings, and nothing elsewhere" do
      assert %{kind: :admin, name: "Admin"} = Navigation.area("/admin/orgs/3", nil, nil)
      assert %{kind: :settings, name: "Your settings"} = Navigation.area("/account", @team, nil)
      assert Navigation.area("/", @team, nil) == nil
      assert Navigation.area("/administrators", @team, nil) == nil
      assert Navigation.area(nil, @team, nil) == nil
    end
  end

  describe "groups/3" do
    test "a team's pages leave out what the team doesn't have" do
      area = Navigation.area("/teams/squamish", @team, nil)
      keys = area |> Navigation.groups("/teams/squamish") |> keys()

      assert "settings-member-logins" in keys
      assert "endorsements" in keys
      refute "settings-mcp" in keys
      refute "proposed-changes" in keys

      team = %{@team | id_cards_enabled: true, mcp_enabled: true}
      keys = "/teams/squamish" |> Navigation.area(team, nil) |> Navigation.groups("/x") |> keys()
      assert ["settings-mcp", "proposed-changes"] -- keys == []
    end

    test "proposed changes show with a count while some wait, even without MCP" do
      groups = "/teams/squamish" |> Navigation.area(@team, nil) |> Navigation.groups("/x", 2)
      link = for {_h, links} <- groups, link <- links, link.key == "proposed-changes", do: link
      assert [%{count: 2}] = link
    end

    test "the first page is current only on itself; others on anything under them" do
      area = Navigation.area("/teams/squamish", @team, nil)
      assert current(Navigation.groups(area, "/teams/squamish")) == ["dashboard"]

      assert current(Navigation.groups(area, "/teams/squamish/activities/7/templates")) == [
               "activities"
             ]

      assert current(Navigation.groups(area, "/teams/squamish/settings")) == ["settings"]

      assert current(Navigation.groups(area, "/teams/squamish/settings/managers")) == [
               "settings-managers"
             ]

      assert current(Navigation.groups(area, "/teams/squamish/members-x")) == []
    end

    test "a group of one link has no heading" do
      groups = "/teams/squamish" |> Navigation.area(@team, nil) |> Navigation.groups("/x")
      headings = Enum.map(groups, &elem(&1, 0))
      assert headings == [nil, "Activities", "People", nil, nil, "Settings"]
    end

    test "a member's 7 pages, with ID card only on a team that has ID cards" do
      member = %Member{team: %{@team | id_cards_enabled: true}}
      area = Navigation.area("/teams/squamish/me", nil, member)

      assert area |> Navigation.groups("/teams/squamish/me/hours") |> keys() == [
               "me",
               "me-card",
               "me-qualifications",
               "me-activities",
               "me-hours",
               "me-tax-credit-letters",
               "me-details"
             ]

      assert current(Navigation.groups(area, "/teams/squamish/me/hours")) == ["me-hours"]
      assert current(Navigation.groups(area, "/teams/squamish/me")) == ["me"]

      area = Navigation.area("/teams/squamish/me", nil, %Member{team: @team})
      refute "me-card" in (area |> Navigation.groups("/x") |> keys())
    end

    test "your settings and pages outside an area have none" do
      assert "/account" |> Navigation.area(nil, nil) |> Navigation.groups("/account") == []
      assert Navigation.groups(nil, "/") == []
    end
  end

  describe "menu_teams/2" do
    test "each team once, A to Z, with the areas it offers" do
      pemberton = %Team{id: 2, name: "pemberton SAR", subdomain: "pemberton"}

      assert [
               %{team: %{id: 2}, team_area: false, member_area: true},
               %{team: %{id: 1}, team_area: true, member_area: true}
             ] =
               Navigation.menu_teams([@team], [
                 %Member{team: @team},
                 %Member{team: pemberton}
               ])
    end
  end

  describe "switch_rows/4" do
    @pemberton %Team{id: 2, name: "Pemberton SAR", subdomain: "pemberton"}

    defp rows(rows),
      do:
        for(
          row <- rows,
          do: {row.heading, for(link <- row.links, do: {link.label, link.current})}
        )

    test "one team with both areas is one row with no heading, the current area marked" do
      area = Navigation.area("/teams/squamish/me", nil, %Member{team: @team})

      assert [%{links: [%{path: "/teams/squamish"}, %{path: "/teams/squamish/me"}]}] =
               rows = Navigation.switch_rows(false, [@team], [%Member{team: @team}], area)

      assert rows(rows) == [{nil, [{"Team area", false}, {"Member area", true}]}]
    end

    test "one area is nothing to switch to" do
      area = Navigation.area("/teams/squamish/me", nil, %Member{team: @team})
      assert Navigation.switch_rows(false, [], [%Member{team: @team}], area) == []
      assert Navigation.switch_rows(true, [], [], Navigation.area("/admin", nil, nil)) == []
    end

    test "two teams each get a row under their name, A to Z, with the areas each offers" do
      area = Navigation.area("/teams/squamish", @team, nil)

      assert area
             |> then(&Navigation.switch_rows(false, [@team], [%Member{team: @pemberton}], &1))
             |> rows() == [
               {"Pemberton SAR", [{"Member area", false}]},
               {"Squamish SAR", [{"Team area", true}]}
             ]
    end

    test "a SAR Duty admin gets a row for Admin first" do
      area = Navigation.area("/admin/orgs", nil, nil)

      assert area
             |> then(&Navigation.switch_rows(true, [@team], [], &1))
             |> rows() == [
               {"SAR Duty", [{"Admin", true}]},
               {"Squamish SAR", [{"Team area", false}]}
             ]
    end

    test "a team that isn't yours marks nothing" do
      area = Navigation.area("/teams/pemberton", @pemberton, nil)
      rows = Navigation.switch_rows(true, [@team], [%Member{team: @team}], area)
      refute Enum.any?(rows, fn row -> Enum.any?(row.links, & &1.current) end)
    end
  end
end
