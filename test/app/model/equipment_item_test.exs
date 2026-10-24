defmodule App.Model.EquipmentItemTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.EquipmentItem

  describe "find_by_code/2" do
    setup do
      %{team: team} = user_with_team_fixture()
      %{team: team}
    end

    test "matches a barcode ignoring case and spaces, before a serial", %{team: team} do
      by_serial = equipment_item_fixture(team, %{serial: "manta 01"})
      by_barcode = equipment_item_fixture(team, %{barcode: "Manta 01 "})

      assert EquipmentItem.find_by_code(team.id, " MANTA 01").id == by_barcode.id
      Repo.delete!(by_barcode)
      assert EquipmentItem.find_by_code(team.id, "Manta 01").id == by_serial.id
    end

    test "matches a 12-digit UPC from the reader's 13-digit EAN", %{team: team} do
      item = equipment_item_fixture(team, %{barcode: "012345678905"})

      assert EquipmentItem.find_by_code(team.id, "0012345678905").id == item.id
      assert EquipmentItem.find_by_code(team.id, "012345678905").id == item.id
    end

    test "finds nothing for a blank code, a part of one, or another team's", %{team: team} do
      equipment_item_fixture(team, %{barcode: "SF0119"})
      %{team: other} = user_with_team_fixture()

      assert EquipmentItem.find_by_code(team.id, "  ") == nil
      assert EquipmentItem.find_by_code(team.id, "SF01") == nil
      assert EquipmentItem.find_by_code(other.id, "SF0119") == nil
    end

    test "prefers an item in service to a retired one with the same barcode", %{team: team} do
      equipment_item_fixture(team, %{barcode: "65#01", status: "retired"})
      current = equipment_item_fixture(team, %{barcode: "65#01"})

      assert EquipmentItem.find_by_code(team.id, "65#01").id == current.id
    end
  end

  describe "held_by_retired_members/2 (#490)" do
    @now ~U[2026-10-23 12:00:00Z]

    test "each retired member's items and what's inside them, by held_by/2's rule" do
      %{team: team} = user_with_team_fixture()
      robin = member_fixture(team, %{name: "Robin Patel", left_at: ~U[2026-09-30 19:00:00Z]})
      casey = member_fixture(team, %{name: "Casey Dhillon", d4h_status: "RETIRED"})
      lee = member_fixture(team, %{name: "Lee Park", left_at: ~U[2027-01-01 00:00:00Z]})
      kit = equipment_item_fixture(team, %{title: "Kit 6", member_id: robin.id})

      pouch =
        equipment_item_fixture(team, %{title: "Pouch", d4h_container_id: kit.d4h_equipment_id})

      equipment_item_fixture(team, %{title: "Splint", d4h_container_id: pouch.d4h_equipment_id})
      equipment_item_fixture(team, %{title: "Old pager", member_id: casey.id, status: "retired"})
      equipment_item_fixture(team, %{title: "GPS 3", member_id: lee.id})
      # Another team's item with the kit's container id, and another team's retired member.
      other = team_fixture()
      equipment_item_fixture(other, %{title: "Stray", d4h_container_id: kit.d4h_equipment_id})
      stranger = member_fixture(other, %{left_at: ~U[2026-01-01 08:00:00Z]})
      equipment_item_fixture(other, %{title: "Their radio", member_id: stranger.id})

      held = EquipmentItem.held_by_retired_members(team, @now)

      assert Enum.map(held, fn {item, member} -> {member.name, item.title} end) == [
               {"Casey Dhillon", "Old pager"},
               {"Robin Patel", "Kit 6"},
               {"Robin Patel", "Pouch"},
               {"Robin Patel", "Splint"}
             ]

      # The same items held_by/2 gives the member page, retired ones aside.
      robin_ids = for {item, %{id: id}} <- held, id == robin.id, do: item.id

      assert Enum.sort(robin_ids) ==
               team |> EquipmentItem.held_by(robin) |> Enum.map(& &1.id) |> Enum.sort()

      assert EquipmentItem.held_by_retired_members(other, ~U[2025-01-01 00:00:00Z]) == []
    end
  end
end
