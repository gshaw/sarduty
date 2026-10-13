defmodule App.Operation.ChangeActivityEquipmentTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.EquipmentItem
  alias App.Model.Tag
  alias App.Operation.ChangeActivityEquipment

  @activity %Activity{d4h_activity_id: 369_989, activity_kind: "exercise"}

  defp item(d4h_id, type \\ "equipment"),
    do: %EquipmentItem{d4h_equipment_id: d4h_id, title: "Item #{d4h_id}", item_type: type}

  test "each item becomes a usage row, with minutes for equipment and km for a vehicle" do
    lines = [
      %{item: item(1), minutes: 90, km: 12},
      %{item: item(2, "vehicle"), minutes: 90, km: 42},
      %{item: item(3, "supply"), minutes: 90, km: 5}
    ]

    assert [radio, truck, rope] = ChangeActivityEquipment.plan_adds(@activity, lines)
    assert radio.action == :create_equipment_usage

    assert radio.new_value == %{
             "d4h_activity_id" => 369_989,
             "d4h_equipment_id" => 1,
             "title" => "Item 1",
             "minutes" => 90,
             "km" => nil
           }

    assert {truck.new_value["minutes"], truck.new_value["km"]} == {nil, 42}
    assert {rope.new_value["minutes"], rope.new_value["km"]} == {nil, nil}
  end

  # D4H would take a second usage and count the item twice.
  test "an item on the activity already, or on an earlier line, is left out" do
    lines = [
      %{item: item(1), minutes: 60},
      %{item: item(2), minutes: 60},
      %{item: item(2), minutes: 30}
    ]

    rows = ChangeActivityEquipment.plan_adds(@activity, lines, [1])
    assert Enum.map(rows, & &1.new_value["d4h_equipment_id"]) == [2]
    assert hd(rows).new_value["minutes"] == 60
  end

  defp tag(d4h_id, title), do: %Tag{d4h_tag_id: d4h_id, title: title}

  # D4H replaces the whole list, so the row keeps what the activity has.
  test "a template's tags join the activity's current tags in one row" do
    tags = [tag(30, "Flat Water"), tag(10, "Primary Hours")]

    row = ChangeActivityEquipment.plan_tags(@activity, [20, 10], tags)

    assert row.action == :set_activity_tags
    assert row.d4h_record_id == 369_989
    assert row.old_value == %{"kind" => "exercise", "tag_ids" => [10, 20]}
    assert row.new_value == %{"tag_ids" => [10, 20, 30], "titles" => ["Flat Water"]}
  end

  # D4H answers a repeated id with a 404.
  test "two templates with the same tag send it once" do
    tags = [tag(30, "Flat Water"), tag(40, "Boat"), tag(30, "Flat Water")]

    row = ChangeActivityEquipment.plan_tags(@activity, [10, 10], tags)

    assert row.new_value["tag_ids"] == [10, 30, 40]
    assert row.new_value["titles"] == ["Flat Water", "Boat"]
  end

  test "no row when the activity has every tag" do
    assert ChangeActivityEquipment.plan_tags(@activity, [10, 30], [tag(30, "Flat Water")]) ==
             nil

    assert ChangeActivityEquipment.plan_tags(@activity, [10], []) == nil
  end
end
