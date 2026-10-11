defmodule App.Adapter.D4H.EquipmentItemTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.EquipmentItem
  alias App.Adapter.D4H.EquipmentUsage

  # Shaped like South Fraser's items in D4H, 2026-10-10.
  defp record(location) do
    %{
      "id" => 186_445,
      "ref" => "COMMAND RADIO DRAWER",
      "type" => "EQUIPMENT",
      "status" => "OPERATIONAL",
      "barcode" => "SF0579",
      "serial" => "",
      "kind" => %{"id" => 22_763, "resourceType" => "EquipmentKind"},
      "location" => location,
      "dateExpires" => "2027-03-01T00:00:00.000Z",
      "parents" => []
    }
  end

  test "an item in a D4H location takes the location's title" do
    item =
      %{"resourceType" => "EquipmentLocation", "id" => 875}
      |> record()
      |> EquipmentItem.build(%{22_763 => "Radio Kit"}, %{875 => "South Fraser SAR Yard"})

    assert item.title == "COMMAND RADIO DRAWER"
    assert item.item_type == "equipment"
    assert item.status == "operational"
    assert item.kind == "Radio Kit"
    assert item.d4h_location_id == 875
    assert item.location_title == "South Fraser SAR Yard"
    assert item.d4h_container_id == nil
    assert item.serial == nil
    assert item.expires_at == ~U[2027-03-01 00:00:00Z]
  end

  test "D4H nests an item in another item through its location" do
    item = %{"resourceType" => "Equipment", "id" => 186_746} |> record() |> EquipmentItem.build()

    assert item.d4h_container_id == 186_746
    assert item.d4h_location_id == nil
  end

  test "an item with a member is theirs, and one with no place has none" do
    held = %{"resourceType" => "Member", "id" => 15_944} |> record() |> EquipmentItem.build()
    assert held.d4h_member_id == 15_944

    nowhere =
      %{"resourceType" => "EquipmentLocation", "id" => nil} |> record() |> EquipmentItem.build()

    assert {nowhere.d4h_location_id, nowhere.d4h_container_id, nowhere.d4h_member_id} ==
             {nil, nil, nil}
  end

  test "a usage names its activity and item, with minutes" do
    usage =
      EquipmentUsage.build(%{
        "id" => 638_650,
        "activity" => %{"id" => 369_989, "resourceType" => "Incident"},
        "equipment" => %{"id" => 377_251, "ref" => "Call-Out Rate"},
        "duration" => 60,
        "distance" => nil,
        "used" => 0
      })

    assert usage.d4h_equipment_usage_id == 638_650
    assert usage.d4h_activity_id == 369_989
    assert usage.d4h_equipment_id == 377_251
    assert usage.minutes == 60
  end
end
