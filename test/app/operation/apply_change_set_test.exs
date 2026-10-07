defmodule App.Operation.ApplyChangeSetTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.AttendanceInfo
  alias App.Model.ChangeSetRow
  alias App.Operation.ApplyChangeSet

  defp info(d4h_attendance_id, d4h_member_id, status),
    do: %AttendanceInfo{
      d4h_attendance_id: d4h_attendance_id,
      d4h_member_id: d4h_member_id,
      status: status
    }

  defp update(old_status),
    do: %ChangeSetRow{
      action: :update_attendance,
      d4h_record_id: 501,
      old_value: %{"status" => old_status},
      new_value: %{"status" => "ATTENDING"}
    }

  defp create(d4h_member_id),
    do: %ChangeSetRow{action: :create_attendance, new_value: %{"d4h_member_id" => d4h_member_id}}

  test "an update goes ahead when D4H still has the status it was proposed from" do
    assert update("requested") |> ApplyChangeSet.check([info(501, 7, "requested")]) == :ok
  end

  test "an update is skipped when D4H changed the row since" do
    assert {:skipped, "D4H changed this since the review. Review again."} =
             update("requested") |> ApplyChangeSet.check([info(501, 7, "attending")])
  end

  test "an update is skipped when the row is gone from D4H" do
    assert {:skipped, "The attendance row is gone from D4H. Review again."} =
             update("requested") |> ApplyChangeSet.check([info(502, 7, "requested")])
  end

  # D4H would accept a second row and count the member's hours twice.
  test "a create is skipped when D4H has a row for the member now" do
    row = create(7)
    assert ApplyChangeSet.check(row, [info(502, 8, "attending")]) == :ok
    assert {:skipped, _} = ApplyChangeSet.check(row, [info(501, 7, "requested")])
  end

  test "group rows aren't checked against attendance" do
    assert %ChangeSetRow{action: :add_group_member} |> ApplyChangeSet.check(nil) == :ok
    assert %ChangeSetRow{action: :remove_group_member} |> ApplyChangeSet.check(nil) == :ok
  end

  @writes ~w(add_group_member remove_group_membership set_attendance create_attendance)
  @applier "lib/app/operation/apply_change_set.ex"

  test "only the applier calls D4H's write functions" do
    callers =
      for path <- Path.wildcard("lib/**/*.{ex,exs,heex}"),
          path not in [@applier, "lib/app/adapter/d4h.ex"],
          source = File.read!(path),
          write <- @writes,
          source =~ ~r/D4H\.#{write}\b/,
          do: "#{path} calls D4H.#{write}"

    assert callers == []
  end
end
