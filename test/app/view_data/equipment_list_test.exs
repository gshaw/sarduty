defmodule App.ViewData.EquipmentListTest do
  use ExUnit.Case, async: true

  alias App.Model.EquipmentItem
  alias App.Model.Member
  alias App.ViewData.EquipmentList

  @now ~U[2026-10-10 12:00:00Z]

  defp item(id, title, attrs \\ []) do
    struct!(
      %EquipmentItem{
        id: id,
        d4h_equipment_id: id,
        title: title,
        item_type: "equipment",
        status: "operational",
        member: nil
      },
      attrs
    )
  end

  # The yard holds a truck, the truck a drawer, the drawer a radio. Sam has a GPS.
  defp items do
    [
      item(4, "Radio 7", d4h_container_id: 3),
      item(1, "SOUTH FRASER 2", location_title: "Yard", item_type: "vehicle"),
      item(3, "02 DRAWER #1", d4h_container_id: 1),
      item(5, "GPS 2", member_id: 9, member: %Member{name: "Sam Ortiz"}),
      item(6, "Old saw", status: "retired", location_title: "Yard"),
      item(7, "Loose rope"),
      item(8, "AED", location_title: "Yard", expires_at: ~U[2026-11-01 00:00:00Z])
    ]
  end

  test "a nested item is in its outermost item's place, inside the items holding it" do
    radio = items() |> EquipmentList.rows() |> Enum.find(&(&1.item.id == 4))

    assert radio.place == "Yard"
    assert radio.inside == "SOUTH FRASER 2 › 02 DRAWER #1"
  end

  test "places go by name, then with members, then no location; contents follow their item" do
    groups = items() |> EquipmentList.rows() |> EquipmentList.group()

    assert Enum.map(groups, &elem(&1, 0)) == ["Yard", "With members", "No location"]

    {"Yard", yard} = hd(groups)

    assert Enum.map(yard, & &1.item.title) == [
             "AED",
             "Old saw",
             "SOUTH FRASER 2",
             "02 DRAWER #1",
             "Radio 7"
           ]
  end

  test "an item a member has shows who has it" do
    gps = items() |> EquipmentList.rows() |> Enum.find(&(&1.item.id == 5))
    assert {gps.place, gps.holder} == {"With members", "Sam Ortiz"}
  end

  test "the filters keep what they say, and search reads titles" do
    rows = EquipmentList.rows(items())
    ids = fn show, q -> rows |> EquipmentList.filter(show, q, @now) |> Enum.map(& &1.item.id) end

    refute 6 in ids.("in-service", "")
    assert ids.("retired", "") == [6]
    assert ids.("with-members", "") == [5]
    assert ids.("expiring", "") == [8]
    assert ids.("in-service", "drawer") == [3]
  end

  test "an item can't nest in itself forever" do
    loop = [item(1, "A", d4h_container_id: 2), item(2, "B", d4h_container_id: 1)]
    assert [_a, _b] = EquipmentList.rows(loop)
  end
end
