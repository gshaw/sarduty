defmodule App.Operation.RefreshD4HData.UpsertAttendancesTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H.AttendanceInfo
  alias App.Model.Attendance
  alias App.Model.NoShow
  alias App.Operation.RefreshD4HData.UpsertAttendances

  # Letter hours come from these rows, so a delete must never reach another team's.
  setup do
    times = %{started_at: ~U[2026-03-14 17:00:00Z], finished_at: ~U[2026-03-14 20:00:00Z]}
    ours = team_fixture()
    theirs = team_fixture()
    activity = activity_fixture(ours, times)
    their_activity = activity_fixture(theirs, times)
    kept = attendance_fixture(activity, member_fixture(ours))
    gone = attendance_fixture(activity, member_fixture(ours))
    their_row = attendance_fixture(their_activity, member_fixture(theirs))

    %{ours: ours, activity: activity, kept: kept, gone: gone, their_row: their_row}
  end

  test "a month's fetch deletes only this team's rows D4H no longer has", context do
    %{ours: ours, kept: kept, gone: gone, their_row: their_row} = context

    UpsertAttendances.delete_stale_between(
      ours.id,
      ~U[2026-03-01 00:00:00Z],
      ~U[2026-04-01 00:00:00Z],
      MapSet.new([kept.d4h_attendance_id])
    )

    assert Repo.get(Attendance, kept.id)
    refute Repo.get(Attendance, gone.id)
    assert Repo.get(Attendance, their_row.id)
  end

  test "a month's fetch leaves rows outside the month", %{ours: ours, kept: kept, gone: gone} do
    UpsertAttendances.delete_stale_between(
      ours.id,
      ~U[2026-04-01 00:00:00Z],
      ~U[2026-05-01 00:00:00Z],
      MapSet.new()
    )

    assert Repo.get(Attendance, kept.id)
    assert Repo.get(Attendance, gone.id)
  end

  test "an activity's fetch deletes only that activity's rows", context do
    %{ours: ours, activity: activity, kept: kept, gone: gone, their_row: their_row} = context
    other_activity = activity_fixture(ours, Map.take(activity, [:started_at, :finished_at]))
    elsewhere = attendance_fixture(other_activity, member_fixture(ours))

    UpsertAttendances.delete_stale_for_activity(
      ours.id,
      activity.id,
      MapSet.new([kept.d4h_attendance_id])
    )

    assert Repo.get(Attendance, kept.id)
    refute Repo.get(Attendance, gone.id)
    assert Repo.get(Attendance, elsewhere.id)
    assert Repo.get(Attendance, their_row.id)
  end

  describe "a no-show" do
    setup %{ours: ours, activity: activity} do
      member = member_fixture(ours)
      row = attendance_fixture(activity, member, %{status: "absent"})
      NoShow.record!(activity, member)
      %{member: member, row: row}
    end

    defp upsert(ctx, status) do
      ctx.ours.id
      |> UpsertAttendances.build_context()
      |> UpsertAttendances.upsert(%AttendanceInfo{
        d4h_attendance_id: ctx.row.d4h_attendance_id,
        d4h_activity_id: ctx.activity.d4h_activity_id,
        d4h_member_id: ctx.member.d4h_member_id,
        started_at: ctx.row.started_at,
        finished_at: ctx.row.finished_at,
        duration_in_minutes: 60,
        status: status
      })
    end

    test "is cleared when D4H changes them to attending", ctx do
      upsert(ctx, "attending")
      assert NoShow.get_all(ctx.activity) == []
    end

    test "stays while D4H has them absent", ctx do
      upsert(ctx, "absent")
      assert [_no_show] = NoShow.get_all(ctx.activity)
    end
  end
end
