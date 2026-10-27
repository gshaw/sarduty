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
      item(4, "Radio 7", d4h_container_id: 3, kind: "Radio"),
      item(1, "SOUTH FRASER 2", location_title: "Yard", item_type: "vehicle"),
      item(3, "02 DRAWER #1", d4h_container_id: 1),
      item(5, "GPS 2", member_id: 9, member: %Member{name: "Sam Ortiz"}, kind: "GPS"),
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
    assert ids.("expiring", "") == [8]
    assert ids.("in-service", "drawer") == [3]
  end

  test "the page opens on places and categories, with counts" do
    rows = EquipmentList.rows(items())

    assert EquipmentList.places(rows) == [{"Yard", 5}, {"With members", 1}, {"No location", 1}]

    assert EquipmentList.categories(rows) == [
             {"GPS", 1},
             {"Radio", 1},
             {"No category", 5}
           ]

    assert EquipmentList.browsing?("in-service", "", "", "")
    refute EquipmentList.browsing?("in-service", "", "Yard", "")
    refute EquipmentList.browsing?("retired", "", "", "")
  end

  test "a place or a category narrows the rows" do
    rows = EquipmentList.rows(items())

    ids = fn place, category ->
      rows |> EquipmentList.narrow(place, category) |> Enum.map(& &1.item.id)
    end

    assert "Yard" |> ids.("") |> Enum.sort() == [1, 3, 4, 6, 8]
    assert ids.("Yard", "Radio") == [4]
    assert ids.("", "GPS") == [5]
    assert ids.("No location", "No category") == [7]
  end

  test "a member is a place: Where lists them after the places, by their local id (#490)" do
    rows =
      EquipmentList.rows([
        item(9, "Radio 22", member_id: 2, member: %Member{name: "Ty Wong"}) | items()
      ])

    assert EquipmentList.place_options(rows) == [
             {"Yard", "Yard"},
             {"With members", "With members"},
             {"No location", "No location"},
             {"With Sam Ortiz", "member-9"},
             {"With Ty Wong", "member-2"}
           ]

    held = %{5 => "Sam Ortiz", 4 => "Sam Ortiz"}
    assert rows |> EquipmentList.narrow("member-9", "", held) |> Enum.map(& &1.item.id) == [4, 5]

    held = %{5 => "Sam Ortiz"}

    assert [{"Sam Ortiz", [%{item: %{id: 5}}]}] =
             rows
             |> EquipmentList.narrow("member-9", "", held)
             |> EquipmentList.group_held(held)
  end

  test "retiring members are a place after With members, a group per holder (#514)" do
    rows =
      EquipmentList.rows([
        item(9, "Radio 22", member_id: 2, member: %Member{name: "Ty Wong"}) | items()
      ])

    assert [_yard, {"With members", _}, {"With retiring members", "retiring"} | _rest] =
             EquipmentList.place_options(rows, true)

    held = %{9 => "Ty Wong", 5 => "Sam Ortiz"}

    assert [{"Sam Ortiz", [%{item: %{id: 5}}]}, {"Ty Wong", [%{item: %{id: 9}}]}] =
             rows
             |> EquipmentList.narrow("retiring", "", held)
             |> EquipmentList.group_held(held)
  end

  test "a member who holds nothing, or a bad member id, keeps no rows" do
    rows = EquipmentList.rows(items())

    for place <- ["member-3", "member-9x", "member-"] do
      narrowed = EquipmentList.narrow(rows, place, "")
      assert narrowed == []
      assert EquipmentList.group_held(narrowed, %{}) == []
    end
  end

  test "Where lists a member who holds only retired items: the team may want them back" do
    rows =
      EquipmentList.rows([
        item(9, "Old radio", member_id: 2, member: %Member{name: "Ty Wong"}, status: "retired")
      ])

    assert EquipmentList.place_options(rows) == [
             {"With members", "With members"},
             {"With Ty Wong", "member-2"}
           ]
  end

  # Sam holds a first aid kit with a pouch in it, the pouch a splint, and a GPS on its own.
  defp held do
    [
      item(1, "First aid kit 6", member_id: 9, kind: "Kit", barcode: "K-006"),
      item(2, "GPS 5", member_id: 9, kind: "GPS"),
      item(3, "Pouch", d4h_container_id: 1),
      item(4, "Splint", d4h_container_id: 3),
      item(5, "Bandages", d4h_container_id: 1)
    ]
  end

  test "a kit's contents follow it, two levels deep, each with the items holding it" do
    rows = EquipmentList.held_rows(held())

    assert Enum.map(rows, &{&1.item.title, &1.inside}) == [
             {"First aid kit 6", ""},
             {"Bandages", "First aid kit 6"},
             {"Pouch", "First aid kit 6"},
             {"Splint", "First aid kit 6 › Pouch"},
             {"GPS 5", ""}
           ]
  end

  test "two kits with one title each keep their own contents" do
    kits = [
      item(1, "First aid kit", member_id: 9),
      item(2, "First aid kit", member_id: 9),
      item(3, "Splint", d4h_container_id: 1),
      item(4, "Bandage", d4h_container_id: 2)
    ]

    assert kits |> EquipmentList.held_rows() |> Enum.map(& &1.item.id) == [1, 3, 2, 4]

    assert [{"With members", rows}] = kits |> EquipmentList.rows() |> EquipmentList.group()
    assert Enum.map(rows, & &1.item.id) == [1, 3, 2, 4]
  end

  test "held items that hold each other stop at the cap" do
    loop = [item(1, "A", d4h_container_id: 2), item(2, "B", d4h_container_id: 1)]
    assert [%{inside: a}, %{inside: b}] = EquipmentList.held_rows(loop)
    assert a != "" and b != ""
  end

  test "an item can't nest in itself forever" do
    loop = [item(1, "A", d4h_container_id: 2), item(2, "B", d4h_container_id: 1)]
    assert [_a, _b] = EquipmentList.rows(loop)
  end
end
