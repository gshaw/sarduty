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

  test "a member is a place: Place lists them after the places, by their local id (#490)" do
    rows =
      EquipmentList.rows([
        item(9, "Radio 22", member_id: 2, member: %Member{name: "Ty Wong"}) | items()
      ])

    assert EquipmentList.place_options(rows) == [
             {"Yard", "Yard"},
             {"With members", "With members"},
             {"No location", "No location"},
             {"Sam Ortiz", "member-9"},
             {"Ty Wong", "member-2"}
           ]

    held = MapSet.new([5, 4])
    assert rows |> EquipmentList.narrow("member-9", "", held) |> Enum.map(& &1.item.id) == [4, 5]

    assert [{"Sam Ortiz", [%{item: %{id: 5}}]}] =
             rows
             |> EquipmentList.narrow("member-9", "", MapSet.new([5]))
             |> EquipmentList.group_held("Sam Ortiz")
  end

  test "a member who holds nothing, or a bad member id, keeps no rows" do
    rows = EquipmentList.rows(items())

    for place <- ["member-3", "member-9x", "member-"] do
      narrowed = EquipmentList.narrow(rows, place, "")
      assert narrowed == []
      assert EquipmentList.group_held(narrowed, "Anyone") == []
    end
  end

  test "Place lists a member who holds only retired items: the team may want them back" do
    rows =
      EquipmentList.rows([
        item(9, "Old radio", member_id: 2, member: %Member{name: "Ty Wong"}, status: "retired")
      ])

    assert EquipmentList.place_options(rows) == [
             {"With members", "With members"},
             {"Ty Wong", "member-2"}
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

  test "a kit's contents follow it, two levels deep, each in the item holding it" do
    rows = EquipmentList.held_rows(held())

    assert Enum.map(rows, &{&1.item.title, &1.in && &1.in.title}) == [
             {"First aid kit 6", nil},
             {"Bandages", "First aid kit 6"},
             {"Pouch", "First aid kit 6"},
             {"Splint", "Pouch"},
             {"GPS 5", nil}
           ]
  end

  test "held items that hold each other stop at the cap" do
    loop = [item(1, "A", d4h_container_id: 2), item(2, "B", d4h_container_id: 1)]
    assert [%{in: %{}}, %{in: %{}}] = EquipmentList.held_rows(loop)
  end

  # Robin retired with a pack holding a radio, and a retired pager. Casey has no leave date.
  defp retired_held do
    robin = %Member{id: 20, name: "Robin Patel", left_at: ~U[2026-09-30 19:00:00Z]}
    casey = %Member{id: 21, name: "Casey Dhillon", d4h_status: "RETIRED"}

    [
      {item(20, "Pack 3", member_id: 20, member: robin), robin},
      {item(21, "Radio 9", d4h_container_id: 20), robin},
      {item(22, "Pager 4", member_id: 20, member: robin, status: "retired"), robin},
      {item(23, "Helmet 9", member_id: 21, member: casey), casey}
    ]
  end

  test "items with retired members move to With retired members, after With members (#490)" do
    held = retired_held()

    rows =
      held
      |> Enum.map(&elem(&1, 0))
      |> Enum.concat(items())
      |> EquipmentList.rows()
      |> EquipmentList.with_retired(held)

    row = fn id -> Enum.find(rows, &(&1.item.id == id)) end

    assert row.(21).place == "With retired members"
    assert {row.(21).holder, row.(21).holder_id} == {"Robin Patel", 20}
    assert row.(21).holder_left_at == ~U[2026-09-30 19:00:00Z]
    assert row.(23).holder_left_at == nil
    assert row.(5).place == "With members"

    assert rows |> EquipmentList.places() |> Enum.map(&elem(&1, 0)) ==
             ["Yard", "With members", "With retired members", "No location"]

    options = EquipmentList.place_options(rows)
    assert {"With retired members", "With retired members"} in options
    assert {"Robin Patel", "member-20"} in options
  end

  test "the team home counts what With retired members lists on All (#490)" do
    assert EquipmentList.retired_held(retired_held()) == %{members: 2, items: 4}
    assert EquipmentList.retired_held([]) == %{members: 0, items: 0}

    [{_pager, _robin} = only_retired] = Enum.filter(retired_held(), &(elem(&1, 0).id == 22))
    assert EquipmentList.retired_held([only_retired]) == %{members: 1, items: 1}
  end

  test "an item can't nest in itself forever" do
    loop = [item(1, "A", d4h_container_id: 2), item(2, "B", d4h_container_id: 1)]
    assert [_a, _b] = EquipmentList.rows(loop)
  end
end
