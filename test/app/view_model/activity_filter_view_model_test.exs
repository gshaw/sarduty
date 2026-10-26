defmodule App.ViewModel.ActivityFilterViewModelTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.ViewModel.ActivityFilterViewModel

  defp options(params) do
    {:ok, options, _changeset} = ActivityFilterViewModel.validate(params)
    options
  end

  defp titles(team, params) do
    team
    |> ActivityFilterViewModel.build_paginated_content(nil, options(params))
    |> Map.fetch!(:entries)
    |> Enum.map(& &1.title)
  end

  describe "chore activities (#575)" do
    setup do
      team = member_logins_team_fixture()
      activity_fixture(team, %{title: "Board meeting", activity_kind: "event"})
      activity_fixture(team, %{title: "Rope rescue night", activity_kind: "exercise"})
      chores = chore_activity_fixture(team, [90, 30])
      %{team: team, chores: chores}
    end

    test "are their own kind, in All but not Events", %{team: team} do
      assert team |> titles(%{}) |> Enum.sort() ==
               ["Board meeting", "Chores: Equipment maintenance", "Rope rescue night"]

      assert titles(team, %{"activity" => "event"}) == ["Board meeting"]
      assert titles(team, %{"activity" => "chores"}) == ["Chores: Equipment maintenance"]
    end

    test "carry their members' accepted minutes", %{team: team} do
      [chores] =
        ActivityFilterViewModel.build_paginated_content(
          team,
          nil,
          options(%{"activity" => "chores"})
        ).entries

      assert chores.chore_minutes == 120

      [meeting] =
        ActivityFilterViewModel.build_paginated_content(
          team,
          nil,
          options(%{"activity" => "event"})
        ).entries

      assert meeting.chore_minutes == nil
    end

    test "count apart from D4H's kinds, and in All", %{team: team} do
      assert ActivityFilterViewModel.kind_counts(team, nil, options(%{})) ==
               %{"all" => 3, "event" => 1, "exercise" => 1, "chores" => 1}
    end

    test "sort by their members' total", %{team: team} do
      chore_activity_fixture(team, [600], %{title: "Chores: Board work"})

      assert titles(team, %{"activity" => "chores", "sort" => "hours"}) ==
               ["Chores: Board work", "Chores: Equipment maintenance"]
    end

    test "only the team's own chore events count", %{team: team} do
      other = member_logins_team_fixture()
      chore_activity_fixture(other, [60])

      assert titles(team, %{"activity" => "chores"}) == ["Chores: Equipment maintenance"]
    end
  end
end
