defmodule App.Operation.ProposeAttendanceChangesTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Operation.ProposeAttendanceChanges

  @activity %Activity{
    id: 1,
    d4h_activity_id: 900,
    started_at: ~U[2026-10-03 02:00:00Z],
    finished_at: ~U[2026-10-03 04:00:00Z]
  }

  @mei %Member{id: 10, d4h_member_id: 110, name: "Mei Chen"}
  @sam %Member{id: 11, d4h_member_id: 111, name: "Sam Ortiz"}
  @members %{10 => @mei, 11 => @sam}

  @sam_absent %Attendance{
    member_id: 11,
    d4h_attendance_id: 5011,
    status: "absent",
    started_at: ~U[2026-10-03 02:00:00Z],
    finished_at: ~U[2026-10-03 04:00:00Z]
  }

  defp plan(requests, attendances \\ [@sam_absent]),
    do: ProposeAttendanceChanges.plan(@activity, attendances, @members, requests)

  test "a member with no row is added with the activity's times" do
    {[row], []} = plan([%{"member_id" => 10, "status" => "attended", "reason" => "Sheet row 3"}])

    assert row.action == :create_attendance
    assert row.member_id == 10
    assert row.reason == "Sheet row 3"

    assert row.new_value == %{
             "status" => "ATTENDING",
             "starts_at" => "2026-10-03T02:00:00Z",
             "ends_at" => "2026-10-03T04:00:00Z",
             "d4h_activity_id" => 900,
             "d4h_member_id" => 110
           }
  end

  test "a member with a row gets an update that remembers what D4H had" do
    {[row], []} =
      plan([
        %{
          "member_id" => 11,
          "status" => "attended",
          "starts_at" => "2026-10-02T19:05:00-07:00",
          "ends_at" => "2026-10-02T21:00:00-07:00"
        }
      ])

    assert row.action == :update_attendance
    assert row.d4h_record_id == 5011
    assert row.old_value["status"] == "absent"
    assert row.reason == "Proposed by an AI agent"

    assert row.new_value == %{
             "status" => "ATTENDING",
             "starts_at" => "2026-10-03T02:05:00Z",
             "ends_at" => "2026-10-03T04:00:00Z"
           }
  end

  test "requests that change nothing or can't apply come back as problems" do
    {rows, problems} =
      plan([
        %{"member_id" => 11, "status" => "absent"},
        %{"member_id" => 10, "status" => "absent"},
        %{"member_id" => 99, "status" => "attended"},
        %{"member_id" => 10, "status" => "maybe"},
        %{"member_id" => 10, "status" => "attended", "starts_at" => "7pm"}
      ])

    assert rows == []

    assert problems == [
             "Sam Ortiz is already absent. Nothing to change.",
             "Mei Chen is already absent. Nothing to change.",
             "No member 99 on this team.",
             "Status must be attended or absent, not \"maybe\".",
             "Times must be ISO 8601 with a time zone, not \"7pm\"."
           ]
  end

  test "a member listed twice keeps the first request" do
    {[row], [problem]} =
      plan([
        %{"member_id" => 10, "status" => "attended"},
        %{"member_id" => 10, "status" => "attended"}
      ])

    assert row.member_id == 10
    assert problem == "Mei Chen is in the list twice. The first one is kept."
  end

  test "the end must come after the start" do
    {[], [problem]} =
      plan([
        %{
          "member_id" => 10,
          "status" => "attended",
          "starts_at" => "2026-10-03T04:00:00Z",
          "ends_at" => "2026-10-03T02:00:00Z"
        }
      ])

    assert problem =~ "The end must be after the start"
  end
end
