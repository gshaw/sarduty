defmodule App.Operation.BuildAttendanceTimesTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.AttendanceScan
  alias App.Model.Member
  alias App.Operation.BuildAttendanceTimes

  # 09:00 to 15:00 UTC.
  @activity %Activity{started_at: ~U[2026-10-10 09:00:00Z], finished_at: ~U[2026-10-10 15:00:00Z]}
  @mei %Member{id: 1, name: "Mei Chen"}
  @raj %Member{id: 2, name: "Raj Patel"}

  defp scan(member, kind, time, attrs \\ []) do
    struct(
      %AttendanceScan{member_id: member.id, member: member, kind: kind, scanned_at: time},
      attrs
    )
  end

  defp times(scans), do: BuildAttendanceTimes.call(@activity, scans)

  test "an arrival within 30 minutes of the start, early or late, counts as the start" do
    [mei, raj] =
      times([
        scan(@mei, "arrived", ~U[2026-10-10 08:30:00Z]),
        scan(@raj, "arrived", ~U[2026-10-10 09:30:00Z])
      ])

    assert mei.arrived_at == ~U[2026-10-10 09:00:00Z]
    assert raj.arrived_at == ~U[2026-10-10 09:00:00Z]
    assert mei.notes == [:no_departure]
  end

  test "an arrival more than 30 minutes from the start keeps its own time" do
    [mei, raj] =
      times([
        scan(@mei, "arrived", ~U[2026-10-10 08:29:00Z]),
        scan(@raj, "arrived", ~U[2026-10-10 09:31:00Z])
      ])

    assert mei.arrived_at == ~U[2026-10-10 08:29:00Z]
    assert raj.arrived_at == ~U[2026-10-10 09:31:00Z]
  end

  test "leaving within 30 minutes of the end, early or late, counts as the end" do
    [mei, raj] =
      times([
        scan(@mei, "left", ~U[2026-10-10 14:30:00Z]),
        scan(@raj, "left", ~U[2026-10-10 15:25:00Z])
      ])

    assert mei.left_at == ~U[2026-10-10 15:00:00Z]
    assert raj.left_at == ~U[2026-10-10 15:00:00Z]
  end

  test "leaving more than 30 minutes from the end keeps its own time" do
    [mei, raj] =
      times([
        scan(@mei, "left", ~U[2026-10-10 14:00:00Z]),
        scan(@raj, "left", ~U[2026-10-10 16:00:00Z])
      ])

    assert mei.left_at == ~U[2026-10-10 14:00:00Z]
    assert raj.left_at == ~U[2026-10-10 16:00:00Z]
  end

  test "a missing scan uses the activity's time, with a note" do
    [mei, raj] =
      times([
        scan(@mei, "arrived", ~U[2026-10-10 09:10:00Z]),
        scan(@raj, "left", ~U[2026-10-10 13:10:00Z])
      ])

    assert {mei.left_at, mei.notes} == {~U[2026-10-10 15:00:00Z], [:no_departure]}
    assert {raj.arrived_at, raj.notes} == {~U[2026-10-10 09:00:00Z], [:no_arrival]}
  end

  test "the latest scan of each kind wins" do
    [row] =
      times([
        scan(@mei, "arrived", ~U[2026-10-10 09:10:00Z], id: 1),
        scan(@mei, "arrived", ~U[2026-10-10 09:40:00Z], id: 2)
      ])

    assert row.arrived_at == ~U[2026-10-10 09:40:00Z]
  end

  test "a typed time stands in for the moment of the scan" do
    [row] =
      times([
        scan(@mei, "arrived", ~U[2026-10-10 12:00:00Z], override_at: ~U[2026-10-10 09:45:00Z])
      ])

    assert row.arrived_at == ~U[2026-10-10 09:45:00Z]
  end

  test "leaving before arriving can't be sent" do
    [row] =
      times([
        scan(@mei, "arrived", ~U[2026-10-10 12:00:00Z]),
        scan(@mei, "left", ~U[2026-10-10 11:00:00Z])
      ])

    assert :left_before_arriving in row.notes
    refute BuildAttendanceTimes.sendable?(row)
  end

  test "times drop their seconds, as D4H keeps whole minutes" do
    [row] = times([scan(@mei, "arrived", ~U[2026-10-10 09:50:42.123456Z])])
    assert row.arrived_at == ~U[2026-10-10 09:50:00Z]
  end
end
