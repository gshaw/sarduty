defmodule App.Operation.RecordD4HChangesRecordingTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.D4HChange
  alias App.Operation.RecordD4HChanges
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.UpsertActivities
  alias App.Operation.RefreshD4HData.UpsertAttendances
  alias App.Operation.RefreshD4HData.UpsertCustomFields
  alias App.Operation.RefreshD4HData.UpsertEquipmentItems
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

  # The row as the sync gets it from D4H.
  defp d4h_row(attendance, attrs) do
    struct!(
      App.Adapter.D4H.AttendanceInfo,
      %{
        d4h_attendance_id: attendance.d4h_attendance_id,
        d4h_member_id: attendance.member.d4h_member_id,
        d4h_activity_id: attendance.activity.d4h_activity_id,
        duration_in_minutes: attendance.duration_in_minutes,
        started_at: attendance.started_at,
        finished_at: attendance.finished_at,
        status: attendance.status
      }
      |> Map.merge(attrs)
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
      UpsertMembers.mark_retired(team.id, MapSet.new(), @now)
    end)

    assert Repo.all(D4HChange) == []
  end

  test "records a member D4H stopped listing as having left", ctx do
    RecordD4HChanges.recording(ctx.team, @now, fn ->
      UpsertMembers.mark_retired(ctx.team.id, MapSet.new(), DateTime.truncate(@now, :second))
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

  # A sync during Remove members' apply (#704) sees the row gone before the copy drops it.
  test "skips a row SAR Duty deleted, and records one deleted in D4H", ctx do
    ours = attendance_fixture(ctx.activity, ctx.member, %{status: "requested"})
    theirs = attendance_fixture(ctx.activity, member_fixture(ctx.team), %{status: "requested"})

    change_set =
      ChangeSet.propose!(
        %ChangeSet{team_id: ctx.team.id, activity_id: ctx.activity.id, source: :remove},
        [
          %ChangeSetRow{
            member_id: ctx.member.id,
            action: :delete_attendance,
            d4h_record_id: ours.d4h_attendance_id,
            old_value: %{"status" => "requested"},
            new_value: %{}
          }
        ]
      )

    [row] = change_set.rows
    ChangeSetRow.record!(row, {:applied, ours.d4h_attendance_id}, @synced)

    RecordD4HChanges.recording(ctx.team, @now, fn ->
      RecordD4HChanges.removed(:attendance, [ours, theirs])
    end)

    assert [%D4HChange{action: :removed, d4h_record_id: id}] = Repo.all(D4HChange)
    assert id == theirs.d4h_attendance_id
  end

  describe "an edit of a team on SAR Duty Records" do
    defp apply_edit(ctx, applied_at) do
      change_set =
        ChangeSet.propose!(%ChangeSet{team_id: ctx.team.id, source: :edit}, [
          %ChangeSetRow{
            member_id: ctx.member.id,
            action: :update_member,
            d4h_record_id: ctx.member.d4h_member_id,
            old_value: %{"name" => ctx.member.name},
            new_value: %{"name" => "Jane Renamed"}
          }
        ])

      [row] = change_set.rows
      ChangeSetRow.record!(row, {:applied, ctx.member.d4h_member_id}, applied_at)
    end

    defp sync_rename(ctx) do
      RecordD4HChanges.recording(ctx.team, @now, fn ->
        RecordD4HChanges.record(:member, ctx.member, %{ctx.member | name: "Jane Renamed"})
      end)
    end

    test "is not recorded again by the sync that copies it back", ctx do
      apply_edit(ctx, ~U[2026-10-09 17:05:00.000000Z])
      sync_rename(ctx)

      assert Repo.all(D4HChange) == []
    end

    test "made before the sync's window doesn't hide a later change", ctx do
      apply_edit(ctx, ~U[2026-10-09 16:00:00.000000Z])
      sync_rename(ctx)

      assert [%D4HChange{record_kind: :member, fields: ["name"]}] = Repo.all(D4HChange)
    end
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

  describe "custom field values (#681)" do
    defp d4h_activity(activity, custom_values) do
      %D4H.Activity{
        d4h_activity_id: activity.d4h_activity_id,
        is_published: activity.is_published,
        title: activity.title,
        description: activity.description,
        address: activity.address,
        activity_kind: activity.activity_kind,
        started_at: activity.started_at,
        finished_at: activity.finished_at,
        tags: activity.tags,
        custom_values: custom_values
      }
    end

    defp save_city_field(team) do
      city = %D4H.CustomField{
        d4h_custom_field_id: 888,
        target: "incident",
        title: "City – Reporting",
        field_type: "single_choice",
        options: [%{"id" => 1, "label" => "Surrey"}, %{"id" => 2, "label" => "Delta"}]
      }

      UpsertCustomFields.save(team.id, [city], @now)
    end

    test "the first copy is the baseline; a change after it is recorded by title", ctx do
      save_city_field(ctx.team)
      assert ctx.activity.custom_values == nil

      RecordD4HChanges.recording(ctx.team, @now, fn ->
        UpsertActivities.upsert(ctx.team.id, d4h_activity(ctx.activity, %{"888" => [1]}))
      end)

      assert Repo.all(D4HChange) == []

      RecordD4HChanges.recording(ctx.team, @now, fn ->
        UpsertActivities.upsert(
          ctx.team.id,
          d4h_activity(ctx.activity, %{"888" => [2], "454" => "PROS 1"})
        )
      end)

      assert [change] = Repo.all(D4HChange)
      assert change.fields == ["custom_values"]

      assert change.old_value == %{
               "custom_values" => %{"City – Reporting" => "Surrey", "Field 454" => nil}
             }

      assert change.new_value == %{
               "custom_values" => %{"City – Reporting" => "Delta", "Field 454" => ~s("PROS 1")}
             }
    end
  end

  describe "an equipment item (#1014)" do
    setup ctx do
      team = team_fixture(%{d4h_access_key: "team-key", d4h_refreshed_at: @synced})
      holder = member_fixture(team, %{name: "Sam Rivera"})

      truck =
        equipment_item_fixture(team, %{
          d4h_equipment_id: 100,
          title: "Rescue 1",
          item_type: "vehicle",
          kind: "Rescue Truck",
          d4h_location_id: 875,
          location_title: "Yard",
          cost_per_km_cents: 67
        })

      Map.merge(ctx, %{team: team, holder: holder, truck: truck})
    end

    defp refresh_equipment(ctx, items) do
      Req.Test.stub(D4H, fn conn ->
        rows =
          case List.last(conn.path_info) do
            "equipment" ->
              items

            "equipment-kinds" ->
              [%{"id" => 1, "title" => "Rescue Truck", "costPerDistance" => 70}]

            "equipment-locations" ->
              [%{"id" => 875, "title" => "Yard"}]

            _other ->
              []
          end

        Req.Test.json(conn, %{"results" => rows, "totalSize" => length(rows)})
      end)

      d4h = D4H.build_context_from_team(ctx.team)

      RecordD4HChanges.recording(ctx.team, @now, fn ->
        UpsertEquipmentItems.call(d4h, ctx.team, Progress.quiet(ctx.team.id))
      end)
    end

    defp truck_row(ctx, attrs) do
      Map.merge(
        %{
          "id" => 100,
          "ref" => "Rescue 1",
          "type" => "VEHICLE",
          "status" => "OPERATIONAL",
          "kind" => %{"id" => 1},
          "costPerDistance" => 67,
          "location" => %{"resourceType" => "EquipmentLocation", "id" => 875}
        },
        attrs.(ctx)
      )
    end

    test "records a move, a status, and a cost in words, never on the holder's page", ctx do
      refresh_equipment(ctx, [
        truck_row(ctx, fn ctx ->
          %{
            "status" => "UNSERVICEABLE",
            "costPerDistance" => nil,
            "location" => %{"resourceType" => "Member", "id" => ctx.holder.d4h_member_id}
          }
        end),
        %{"id" => 300, "ref" => "Radio 9", "type" => "EQUIPMENT", "status" => "OPERATIONAL"}
      ])

      truck_id = ctx.truck.id
      assert [moved] = D4HChange |> where(equipment_item_id: ^truck_id) |> Repo.all()
      assert moved.fields == ["status", "where", "cost_per_km_cents"]
      assert moved.member_id == nil

      assert moved.old_value == %{
               "status" => "operational",
               "where" => "Yard",
               "cost_per_km_cents" => 67
             }

      assert moved.new_value == %{
               "status" => "unserviceable",
               "where" => "Sam Rivera",
               "cost_per_km_cents" => 70
             }

      assert [%D4HChange{action: :added}] =
               D4HChange |> where([c], c.equipment_item_id != ^truck_id) |> Repo.all()

      # D4H deleting the item deletes its page, and its history with it.
      Repo.delete!(ctx.truck)
      assert D4HChange |> where(equipment_item_id: ^truck_id) |> Repo.all() == []
    end

    test "an unchanged item records nothing", ctx do
      refresh_equipment(ctx, [truck_row(ctx, fn _ctx -> %{} end)])
      assert Repo.all(D4HChange) == []
    end

    test "Change item is not recorded again by the sync that copies it back", ctx do
      change_set =
        ChangeSet.propose!(%ChangeSet{team_id: ctx.team.id, source: :edit}, [
          %ChangeSetRow{
            action: :update_equipment_item,
            d4h_record_id: 100,
            old_value: %{"status" => "operational"},
            new_value: %{"status" => "lost"}
          }
        ])

      [row] = change_set.rows
      ChangeSetRow.record!(row, {:applied, 100}, ~U[2026-10-09 17:05:00.000000Z])

      refresh_equipment(ctx, [truck_row(ctx, fn _ctx -> %{"status" => "LOST"} end)])
      assert Repo.all(D4HChange) == []
    end
  end
end
