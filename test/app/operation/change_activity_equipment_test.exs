defmodule App.Operation.ChangeActivityEquipmentTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.EquipmentItem
  alias App.Operation.ChangeActivityEquipment

  @activity %Activity{d4h_activity_id: 369_989}

  defp item(d4h_id, type \\ "equipment"),
    do: %EquipmentItem{d4h_equipment_id: d4h_id, title: "Item #{d4h_id}", item_type: type}

  test "each item becomes a usage row, with minutes for equipment only" do
    lines = [%{item: item(1), minutes: 90}, %{item: item(2, "vehicle"), minutes: 90}]

    assert [radio, truck] = ChangeActivityEquipment.plan_adds(@activity, lines)
    assert radio.action == :create_equipment_usage

    assert radio.new_value == %{
             "d4h_activity_id" => 369_989,
             "d4h_equipment_id" => 1,
             "title" => "Item 1",
             "minutes" => 90
           }

    assert truck.new_value["minutes"] == nil
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
end
