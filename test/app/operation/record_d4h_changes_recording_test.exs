defmodule App.Operation.RecordD4HChangesRecordingTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.D4HChange
  alias App.Operation.RecordD4HChanges
  alias App.Operation.RefreshD4HData.UpsertAttendances
  alias App.Operation.RefreshD4HData.UpsertGroupMemberships
  alias App.Operation.RefreshD4HData.UpsertMembers

  @now ~U[2026-10-09 17:10:00.000000Z]
  @synced ~U[2026-10-09 17:00:00.000000Z]

  setup do
    team = team_fixture(%{d4h_refreshed_at: @synced, d4h_synced_at: @synced})
    member = member_fixture(team)
    activity = activity_fixture(team)
    %{team: team, member: member, activity: activity}
  end

  defp d4h_row(attendance, attrs) do
    Map.merge(
      %{
        d4h_attendance_id: attendance.d4h_attendance_id,
        d4h_member_id: attendance.member.d4h_member_id,
        d4h_activity_id: attendance.activity.d4h_activity_id,
        duration_in_minutes: attendance.duration_in_minutes,
        started_at: attendance.started_at,
        finished_at: attendance.finished_at,
        status: attendance.status
      },
      attrs
    )
  end

  defp upsert(team, row) do
    team.id |> UpsertAttendances.build_context() |> UpsertAttendances.upsert(row)
  end

  test "records a change the sync saw, with the window it happened in", ctx do
    attendance =
      ctx.activity
      |> attendance_fixture(ctx.member, %{status: "absent"})
      |> Repo.preload([:member, :activity])

    RecordD4HChanges.recording(ctx.team, @now, fn ->
      upsert(ctx.team, d4h_row(attendance, %{status: "attending"}))
    end)

    assert [change] = Repo.all(D4HChange)
    assert change.record_kind == :attendance
    assert change.action == :changed
    assert change.member_id == ctx.member.id
    assert change.activity_id == ctx.activity.id
    assert change.old_value == %{"status" => "absent"}
    assert change.new_value == %{"status" => "attending"}
    assert change.seen_after == @synced
    assert change.seen_at == @now
  end

  test "records nothing outside a run", ctx do
    attendance =
      ctx.activity
      |> attendance_fixture(ctx.member, %{status: "absent"})
      |> Repo.preload([:member, :activity])

    upsert(ctx.team, d4h_row(attendance, %{status: "attending"}))
    assert Repo.all(D4HChange) == []
  end

  test "records nothing on a team's first refresh, which is the baseline", ctx do
    team = %{ctx.team | d4h_refreshed_at: nil}

    RecordD4HChanges.recording(team, @now, fn ->
      UpsertMembers.mark_departed(team.id, MapSet.new(), @now)
    end)

    assert Repo.all(D4HChange) == []
  end

  test "records a member D4H stopped listing as having left", ctx do
    RecordD4HChanges.recording(ctx.team, @now, fn ->
      UpsertMembers.mark_departed(ctx.team.id, MapSet.new(), DateTime.truncate(@now, :second))
    end)

    assert [change] = Repo.all(D4HChange)
    assert change.record_kind == :member
    assert change.fields == ["left_at"]
    assert change.new_value == %{"left_at" => "2026-10-09T17:10:00Z"}
  end

  test "records removed group memberships with the group's name", ctx do
    group = group_fixture(ctx.team, %{title: "Callout"})
    group_member_fixture(group, ctx.member)

    RecordD4HChanges.recording(ctx.team, @now, fn ->
      UpsertGroupMemberships.delete_stale(ctx.team.id, MapSet.new())
    end)

    assert [change] = Repo.all(D4HChange)
    assert change.record_kind == :group_membership
    assert change.action == :removed
    assert change.label == "Callout"
    assert change.group_id == group.id
  end

  test "skips SAR Duty's own write, already on the page from its change set", ctx do
    attendance =
      ctx.activity
      |> attendance_fixture(ctx.member, %{status: "absent"})
      |> Repo.preload([:member, :activity])

    change_set =
      ChangeSet.propose!(
        %ChangeSet{team_id: ctx.team.id, activity_id: ctx.activity.id, source: :door},
        [
          %ChangeSetRow{
            member_id: ctx.member.id,
            action: :update_attendance,
            d4h_record_id: attendance.d4h_attendance_id,
            old_value: %{"status" => "ABSENT"},
            new_value: %{"status" => "ATTENDING"}
          }
        ]
      )

    [row] = change_set.rows
    ChangeSetRow.record!(row, {:applied, attendance.d4h_attendance_id}, @synced)

    RecordD4HChanges.recording(ctx.team, @now, fn ->
      upsert(ctx.team, d4h_row(attendance, %{status: "attending"}))
    end)

    assert Repo.all(D4HChange) == []
  end

  test "keeps attendance and awards past 2 years, and prunes the rest", ctx do
    old = DateTime.add(@now, -800, :day)

    for kind <- [:attendance, :award, :member, :group_membership] do
      D4HChange.insert!(%D4HChange{
        team_id: ctx.team.id,
        member_id: ctx.member.id,
        record_kind: kind,
        action: :changed,
        seen_at: old
      })
    end

    assert D4HChange.prune(@now) == 2

    assert D4HChange |> Repo.all() |> Enum.map(& &1.record_kind) |> Enum.sort() == [
             :attendance,
             :award
           ]
  end
end
