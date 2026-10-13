defmodule App.Operation.SaveKitTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Kit
  alias App.Operation.SaveKit

  test "a kit keeps the team's tags, each once, and may have no items" do
    team = team_fixture()
    boat = tag_fixture(team, "Boat")
    water = tag_fixture(team, "Flat Water")
    other = tag_fixture(team_fixture(), "Other team")

    {:ok, kit} =
      SaveKit.save(team, nil, %{"title" => "Boat training"}, [], [
        water.id,
        boat.id,
        water.id,
        other.id
      ])

    kit = Kit.find!(team, kit.id)
    assert kit.kit_items == []
    assert kit |> Kit.tags() |> Enum.map(& &1.title) == ["Boat", "Flat Water"]

    {:ok, _kit} = SaveKit.save(team, kit, %{}, [], [water.id])
    assert team |> Kit.find!(kit.id) |> Kit.tags() |> Enum.map(& &1.title) == ["Flat Water"]
  end

  test "a kit keeps the team's groups, each once" do
    team = team_fixture()
    rope = group_fixture(team, %{title: "Rope"})
    managers = group_fixture(team, %{title: "Search Managers"})
    other = group_fixture(team_fixture(), %{title: "Other team"})

    {:ok, kit} =
      SaveKit.save(team, nil, %{"title" => "Managers' training"}, [], [], [
        managers.id,
        rope.id,
        managers.id,
        other.id
      ])

    kit = Kit.find!(team, kit.id)
    assert kit |> Kit.groups() |> Enum.map(& &1.title) == ["Rope", "Search Managers"]

    {:ok, _kit} = SaveKit.save(team, kit, %{}, [], [], [rope.id])
    assert team |> Kit.find!(kit.id) |> Kit.groups() |> Enum.map(& &1.title) == ["Rope"]
  end
end
