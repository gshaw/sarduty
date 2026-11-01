defmodule App.Operation.ApplyChangeSetTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.AttendanceInfo
  alias App.Adapter.D4H.EquipmentUsage
  alias App.Adapter.D4H.QualificationAward
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
    assert {:skipped, "This changed since you reviewed it. Review again."} =
             update("requested") |> ApplyChangeSet.check([info(501, 7, "attending")])
  end

  test "an update is skipped when the row is gone from D4H" do
    assert {:skipped, "The attendance row was deleted. Review again."} =
             update("requested") |> ApplyChangeSet.check([info(502, 7, "requested")])
  end

  # The exception to skip-if-changed (#444): a member who said Can't make it in D4H a
  # moment ago, before the copy caught up, then taps I'll be there here, is signed up.
  test "a member's reply wins over the status D4H has now" do
    row = update("requested")

    assert ApplyChangeSet.check(row, [info(501, 7, "absent")], :member) == :ok
    assert ApplyChangeSet.check(row, [info(501, 7, "attending")], :member) == :ok

    assert {:skipped, _} = ApplyChangeSet.check(row, [info(501, 7, "absent")], :door)
    assert {:skipped, _} = ApplyChangeSet.check(row, [info(501, 7, "absent")], :agent)
  end

  test "a member's reply is skipped when their row is gone from D4H" do
    assert {:skipped, "The attendance row was deleted."} =
             update("requested") |> ApplyChangeSet.check([info(502, 7, "requested")], :member)
  end

  # D4H would accept a second row and count the member's hours twice.
  test "a create is skipped when D4H has a row for the member now" do
    row = create(7)
    assert ApplyChangeSet.check(row, [info(502, 8, "attending")]) == :ok
    assert {:skipped, _} = ApplyChangeSet.check(row, [info(501, 7, "requested")])
  end

  # Remove members (#704): each row with its own status from the copy.
  test "a delete goes ahead on the status it was proposed from, or a row gone already" do
    row = %ChangeSetRow{
      action: :delete_attendance,
      d4h_record_id: 501,
      old_value: %{"status" => "requested"}
    }

    assert ApplyChangeSet.check(row, [info(501, 7, "requested")]) == :ok
    assert ApplyChangeSet.check(row, [info(502, 7, "attending")]) == :ok

    assert {:skipped, "This changed since you reviewed it. Review again."} =
             ApplyChangeSet.check(row, [info(501, 7, "attending")])
  end

  test "group rows aren't checked against attendance" do
    assert %ChangeSetRow{action: :add_group_member} |> ApplyChangeSet.check(nil) == :ok
    assert %ChangeSetRow{action: :remove_group_member} |> ApplyChangeSet.check(nil) == :ok
  end

  test "an equipment add is skipped when D4H has the item on the activity now" do
    row = %ChangeSetRow{action: :create_equipment_usage, new_value: %{"d4h_equipment_id" => 7}}

    assert ApplyChangeSet.check(row, [%EquipmentUsage{d4h_equipment_id: 8}]) == :ok
    assert {:skipped, _} = ApplyChangeSet.check(row, [%EquipmentUsage{d4h_equipment_id: 7}])
  end

  test "an equipment remove is skipped when D4H has dropped the usage already" do
    row = %ChangeSetRow{action: :delete_equipment_usage, d4h_record_id: 40}

    assert ApplyChangeSet.check(row, [%EquipmentUsage{d4h_equipment_usage_id: 40}]) == :ok
    assert {:skipped, _} = ApplyChangeSet.check(row, [])
  end

  @writes ~w(add_group_member remove_group_membership set_attendance create_attendance
             create_member update_member retire_member rejoin_member set_member_photo
             remove_member_photo create_activity
             update_activity delete_activity create_qualification update_qualification
             delete_qualification award_qualification remove_award create_group update_group
             delete_group create_equipment_usage delete_equipment_usage set_activity_tags
             create_equipment_item
             update_equipment_item delete_equipment_item delete_attendance publish_activity
             upload_document create_whiteboard_note update_whiteboard_note
             delete_whiteboard_note create_location_bookmark update_location_bookmark
             delete_location_bookmark)
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

  # D4H's API can't remove an award, so a second one would stay (#493). Which day an
  # award starts on is QualificationAward.starts_on?/2's test.
  test "a certificate's award is skipped when D4H has it from the same day" do
    row = %ChangeSetRow{
      action: :award_qualification,
      new_value: %{"d4h_qualification_id" => 4, "starts_at" => "2026-10-01T07:00:00Z"}
    }

    same = %QualificationAward{d4h_qualification_id: 4, starts_at: ~U[2026-10-01 00:00:00Z]}
    earlier = %{same | starts_at: ~U[2025-10-01 00:00:00Z]}
    other = %{same | d4h_qualification_id: 5}

    assert ApplyChangeSet.check(row, {:awards, [earlier, other]}) == :ok

    assert {:skipped, "This member has this award already."} =
             ApplyChangeSet.check(row, {:awards, [same]})
  end

  test "a certificate goes only on an award D4H has" do
    row = %ChangeSetRow{
      action: :attach_award_document,
      new_value: %{"created_in_set" => true, "d4h_award_id" => nil}
    }

    assert {:failed, _text} = ApplyChangeSet.check(row, {:awards, []})
    filled = put_in(row.new_value["d4h_award_id"], 3)
    assert ApplyChangeSet.check(filled, {:awards, []}) == :ok
  end

  test "a tags row goes only when D4H has the tags the page opened with" do
    row = %ChangeSetRow{action: :set_activity_tags, old_value: %{"tag_ids" => [1, 2]}}

    assert ApplyChangeSet.check(row, {:tags, [1, 2]}) == :ok
    assert {:skipped, _text} = ApplyChangeSet.check(row, {:tags, [1, 2, 3]})
  end
end
