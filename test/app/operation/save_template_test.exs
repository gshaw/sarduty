defmodule App.Operation.SaveTemplateTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Template
  alias App.Operation.SaveTemplate

  test "a template keeps the team's tags, each once, and may have no items" do
    team = team_fixture()
    boat = tag_fixture(team, "Boat")
    water = tag_fixture(team, "Flat Water")
    other = tag_fixture(team_fixture(), "Other team")

    {:ok, template} =
      SaveTemplate.save(team, nil, %{"title" => "Boat training"}, [], [
        water.id,
        boat.id,
        water.id,
        other.id
      ])

    template = Template.find!(team, template.id)
    assert template.template_items == []
    assert template |> Template.tags() |> Enum.map(& &1.title) == ["Boat", "Flat Water"]

    {:ok, _template} = SaveTemplate.save(team, template, %{}, [], [water.id])

    assert team |> Template.find!(template.id) |> Template.tags() |> Enum.map(& &1.title) == [
             "Flat Water"
           ]
  end

  test "a template keeps the team's groups, each once" do
    team = team_fixture()
    rope = group_fixture(team, %{title: "Rope"})
    managers = group_fixture(team, %{title: "Search Managers"})
    other = group_fixture(team_fixture(), %{title: "Other team"})

    {:ok, template} =
      SaveTemplate.save(team, nil, %{"title" => "Managers' training"}, [], [], [
        managers.id,
        rope.id,
        managers.id,
        other.id
      ])

    template = Template.find!(team, template.id)
    assert template |> Template.groups() |> Enum.map(& &1.title) == ["Rope", "Search Managers"]

    {:ok, _template} = SaveTemplate.save(team, template, %{}, [], [], [rope.id])

    assert team |> Template.find!(template.id) |> Template.groups() |> Enum.map(& &1.title) == [
             "Rope"
           ]
  end
end
