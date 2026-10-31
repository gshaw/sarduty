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
      SaveTemplate.save(team, nil, %{"title" => "Boat training"},
        tag_ids: [water.id, boat.id, water.id, other.id]
      )

    template = Template.find!(team, template.id)
    assert template.template_items == []
    assert template |> Template.tags() |> Enum.map(& &1.title) == ["Boat", "Flat Water"]

    {:ok, _template} = SaveTemplate.save(team, template, %{}, tag_ids: [water.id])

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
      SaveTemplate.save(team, nil, %{"title" => "Managers' training"},
        group_ids: [managers.id, rope.id, managers.id, other.id]
      )

    template = Template.find!(team, template.id)
    assert template |> Template.groups() |> Enum.map(& &1.title) == ["Rope", "Search Managers"]

    {:ok, _template} = SaveTemplate.save(team, template, %{}, group_ids: [rope.id])

    assert team |> Template.find!(template.id) |> Template.groups() |> Enum.map(& &1.title) == [
             "Rope"
           ]
  end

  test "saving one part leaves the others" do
    team = team_fixture()
    water = tag_fixture(team, "Flat Water")
    {:ok, template} = SaveTemplate.save(team, nil, %{"title" => "Boat"}, tag_ids: [water.id])
    template = Template.find!(team, template.id)

    {:ok, _template} = SaveTemplate.save(team, template, %{"title" => "Boat training"})

    template = Template.find!(team, template.id)
    assert template.title == "Boat training"
    assert template |> Template.tags() |> Enum.map(& &1.title) == ["Flat Water"]
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

    params = %{"title" => "Lost hiker", "activity_kind" => "incident"}
    {:ok, template} = SaveTemplate.save(team, nil, params, fields: fields)

    assert template.activity_kind == "incident"
    assert template.custom_values == %{id.(cause) => [2], id.(agency) => "RCMP"}

    # Any kind holds no values.
    {:ok, template} = SaveTemplate.save(team, template, %{"activity_kind" => ""})
    assert template.activity_kind == nil
    assert template.custom_values == %{}
  end

  test "a template's kind is one of D4H's three" do
    {:error, changeset} =
      SaveTemplate.save(team_fixture(), nil, %{"title" => "X", "activity_kind" => "callout"})

    assert changeset.errors[:activity_kind]
  end

  test "a template's tags leave out the team's hours tags" do
    team = team_fixture()
    water = tag_fixture(team, "Flat Water")
    primary = tag_fixture(team, "Primary Hours")
    secondary = tag_fixture(team, "Secondary Hours")

    {:ok, template} =
      SaveTemplate.save(team, nil, %{"title" => "Boat"},
        tag_ids: [water.id, primary.id, secondary.id]
      )

    assert team |> Template.find!(template.id) |> Template.tags() |> Enum.map(& &1.title) == [
             "Flat Water"
           ]
  end

  test "Change details keeps the activity's details, with the duration as a chore's time" do
    team = team_fixture()
    template = template_fixture(team, "Monday night training")

    {:ok, template} =
      SaveTemplate.save_details(team, template, %{
        "activity_title" => " ",
        "start_time" => "19:00",
        "duration" => "2.5",
        "place" => "49.1, -123.1",
        "hours" => "secondary",
        "description" => "Bring your radio."
      })

    template = Repo.reload!(template)
    assert template.activity_title == nil
    assert template.start_time == ~T[19:00:00]
    assert template.duration_minutes == 150
    assert template.coordinate == "49.10000,-123.10000"
    assert template.hours == "secondary"
    assert template.description =~ "Bring your radio."
    assert Template.build_details_changeset(template).data.duration == "2h 30m"

    {:ok, template} = SaveTemplate.save_details(team, template, %{"duration" => "30"})
    assert Repo.reload!(template).duration_minutes == 30

    {:ok, template} = SaveTemplate.save_details(team, template, %{"duration" => ""})
    assert Repo.reload!(template).duration_minutes == nil
  end

  test "Change details refuses a duration it can't read, none, or over a week" do
    team = team_fixture()
    template = template_fixture(team)

    for {duration, error} <- [
          {"abc", "Enter the duration like 45m, 2h, or 2.5h."},
          {"-1", "Enter the duration like 45m, 2h, or 2.5h."},
          {"0", "Enter a duration over 0."},
          {"169h", "Enter up to 168h."}
        ] do
      assert {:error, changeset} =
               SaveTemplate.save_details(team, template, %{"duration" => duration})

      assert {^error, _opts} = changeset.errors[:duration]
    end

    assert {:ok, template} = SaveTemplate.save_details(team, template, %{"duration" => "36h"})
    assert template.duration_minutes == 36 * 60
  end
end
