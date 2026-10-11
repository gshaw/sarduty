defmodule App.Operation.RefreshD4HData.UpsertEquipmentTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.KitItem
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.UpsertEquipmentItems
  alias App.Operation.RefreshD4HData.UpsertEquipmentUsages

  defp page(results), do: %{"results" => results, "totalSize" => length(results)}

  defp stub(lists) do
    Req.Test.stub(D4H, fn conn ->
      list = conn.path_info |> List.last()

      case Map.fetch(lists, list) do
        {:ok, {:status, status}} -> Plug.Conn.send_resp(conn, status, "")
        {:ok, rows} -> Req.Test.json(conn, page(rows))
        :error -> Req.Test.json(conn, page([]))
      end
    end)
  end

  defp run(team) do
    d4h = D4H.build_context_from_team(team)
    progress = Progress.quiet(team.id)
    UpsertEquipmentItems.call(d4h, team, progress)
    UpsertEquipmentUsages.call(d4h, team, progress)
  end

  test "copies items with their place and usages, and drops what D4H deleted" do
    team = team_fixture(%{d4h_access_key: "team-key"})
    member = member_fixture(team)
    activity = activity_fixture(team)
    gone = equipment_item_fixture(team)
    kit_fixture(team, "Old kit", [{gone, 60}])

    stub(%{
      "equipment-kinds" => [%{"id" => 1, "title" => "Rescue Truck"}],
      "equipment-locations" => [%{"id" => 875, "title" => "South Fraser SAR Yard"}],
      "equipment" => [
        %{
          "id" => 100,
          "ref" => "SOUTH FRASER 2",
          "type" => "VEHICLE",
          "status" => "OPERATIONAL",
          "kind" => %{"id" => 1},
          "location" => %{"resourceType" => "EquipmentLocation", "id" => 875}
        },
        %{
          "id" => 101,
          "ref" => "GPS 2",
          "type" => "EQUIPMENT",
          "status" => "OPERATIONAL",
          "location" => %{"resourceType" => "Member", "id" => member.d4h_member_id}
        }
      ],
      "equipment-usages" => [
        %{
          "id" => 5000,
          "activity" => %{"resourceType" => "Exercise", "id" => activity.d4h_activity_id},
          "equipment" => %{"id" => 101},
          "duration" => 120
        },
        # An activity this copy doesn't have is skipped.
        %{
          "id" => 5001,
          "activity" => %{"resourceType" => "Incident", "id" => 1},
          "equipment" => %{"id" => 100}
        }
      ]
    })

    run(team)

    truck = Repo.get_by!(EquipmentItem, team_id: team.id, d4h_equipment_id: 100)

    assert {truck.kind, truck.location_title, truck.item_type} ==
             {"Rescue Truck", "South Fraser SAR Yard", "vehicle"}

    assert Repo.get_by!(EquipmentItem, team_id: team.id, d4h_equipment_id: 101).member_id ==
             member.id

    assert [usage] = Repo.all(EquipmentUsage)
    assert {usage.activity_id, usage.minutes} == {activity.id, 120}

    refute Repo.get(EquipmentItem, gone.id)
    assert Repo.all(KitItem) == []
  end

  test "a team without D4H's equipment module has none, and the refresh goes on" do
    team = team_fixture(%{d4h_access_key: "team-key"})
    stub(%{"equipment-kinds" => {:status, 403}, "equipment-usages" => {:status, 403}})

    assert {0, _progress} = run(team)
  end
end
