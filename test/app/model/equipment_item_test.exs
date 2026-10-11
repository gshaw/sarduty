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
end
