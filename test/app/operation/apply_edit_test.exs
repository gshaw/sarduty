defmodule App.Operation.ApplyEditTest do
  use ExUnit.Case, async: true

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Team
  alias App.Operation.ApplyEdit

  defp member_row(new_value),
    do: %ChangeSetRow{action: :update_member, d4h_record_id: 70, new_value: new_value}

  defp takes?(new_value), do: new_value |> member_row() |> ApplyEdit.d4h_takes?()

  test "a D4H team sends a member's details and custom fields" do
    assert takes?(%{"position" => "MIT", "email" => "pat@example.com"})

    assert takes?(%{
             "name" => "Pat Example",
             "ref_id" => "12",
             "phone" => "902-555-0100",
             "address" => "1 Main St",
             "status" => "OBSERVER",
             "joined_at" => "2025-03-01T04:00:00Z",
             "custom_values" => %{"630" => "SF 12"}
           })
  end

  test "access, or anything else D4H's PATCH is not sent from here, is refused" do
    refute takes?(%{"permission" => 2})
    refute takes?(%{"position" => "MIT", "permission" => 0})
    refute takes?(%{"notes" => "Moved away"})
    refute takes?(%{})

    refute ApplyEdit.d4h_takes?(%ChangeSetRow{
             action: :create_member,
             new_value: %{"name" => "A"}
           })

    refute ApplyEdit.d4h_takes?(%ChangeSetRow{action: :retire_member, new_value: %{}})
  end

  test "an item sends only its status, barcode, and custom fields" do
    item = %ChangeSetRow{action: :update_equipment_item, new_value: %{"custom_values" => %{}}}
    assert ApplyEdit.d4h_takes?(item)
    assert ApplyEdit.d4h_takes?(%{item | new_value: %{"status" => "lost", "barcode" => "R1"}})
    refute ApplyEdit.d4h_takes?(%{item | new_value: %{"title" => "Rope"}})
    refute ApplyEdit.d4h_takes?(%{item | new_value: %{"status" => "lost", "serial" => "9"}})
    refute ApplyEdit.d4h_takes?(%{item | new_value: %{}})
    refute ApplyEdit.d4h_takes?(%ChangeSetRow{action: :delete_equipment_item, new_value: %{}})
  end

  test "a D4H team's member row with access goes nowhere and says where to change it" do
    team = %Team{id: 1, d4h_api_host: "api.ca.d4h.org"}
    row = member_row(%{"position" => "MIT", "permission" => 0})

    assert ApplyEdit.call(team, %User{id: 1}, row, DateTime.utc_now()) ==
             {:error, "Change this in D4H."}
  end
end
