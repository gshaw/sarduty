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

  test "a template keeps the filled values of its kind's fields only" do
    team = team_fixture()
    cause = custom_field_fixture(team, %{field_type: "single_choice", title: "Primary Cause"})
    agency = custom_field_fixture(team, %{title: "Requesting Agency"})
    file = custom_field_fixture(team, %{title: "Agency File #"})
    leader = custom_field_fixture(team, %{target: "event", title: "Event Leader"})
    id = &Integer.to_string(&1.d4h_custom_field_id)

    fields = %{
      id.(cause) => "2",
      id.(agency) => " RCMP ",
      id.(file) => "",
      id.(leader) => "Sam"
    }

    params = %{"title" => "Lost hiker", "activity_kind" => "incident", "fields" => fields}
    {:ok, template} = SaveTemplate.save(team, nil, params, [])

    assert template.activity_kind == "incident"
    assert template.custom_values == %{id.(cause) => [2], id.(agency) => "RCMP"}

    # Any kind holds no values.
    {:ok, template} = SaveTemplate.save(team, template, %{"activity_kind" => ""}, [])
    assert template.activity_kind == nil
    assert template.custom_values == %{}
  end

  test "a template's kind is one of D4H's three" do
    {:error, changeset} =
      SaveTemplate.save(team_fixture(), nil, %{"title" => "X", "activity_kind" => "callout"}, [])

    assert changeset.errors[:activity_kind]
  end
end
