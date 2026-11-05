defmodule App.Operation.ChangeAttendanceTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AttendanceStub
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.NoShow
  alias App.Operation.ChangeAttendance
  alias App.Operation.SendAttendanceToD4H

  defp member(id), do: %Member{id: id, d4h_member_id: 100 + id, name: "Member #{id}"}

  defp row(member, id, status),
    do: %Attendance{
      id: id,
      member_id: member.id,
      d4h_attendance_id: 900 + id,
      status: status,
      started_at: ~U[2026-10-28 02:00:00Z],
      finished_at: ~U[2026-10-28 03:00:00Z]
    }

  @activity %Activity{
    started_at: ~U[2026-10-28 02:00:00Z],
    finished_at: ~U[2026-10-28 04:30:00Z]
  }

  describe "plan/3" do
    test "Attended passes over the attended, and Absent the absent (V)" do
      casey = member(1)
      riley = member(2)
      rows = [row(casey, 1, "attending"), row(riley, 2, "requested")]
      checked = [{casey, "attending"}, {riley, "requested"}]

      assert %{change: [%{member: ^riley}], not_changed: []} =
               ChangeAttendance.plan(:attended, checked, rows)

      assert %{change: [%{member: ^casey}, %{member: ^riley}]} =
               ChangeAttendance.plan(:absent, checked, rows)

      assert %{change: [_, _]} = ChangeAttendance.plan(:remove, checked, rows)
      refute ChangeAttendance.changes?(:attended, "attending")
      assert ChangeAttendance.changes?(:remove, "absent")
    end

    test "Absent marks every row not absent; Remove deletes every row" do
      jordan = member(1)
      rows = [row(jordan, 1, "attending"), row(jordan, 2, "absent"), row(jordan, 3, "requested")]

      assert %{change: [%{rows: absent_rows}]} =
               ChangeAttendance.plan(:absent, [{jordan, "attending"}], rows)

      assert Enum.map(absent_rows, & &1.id) == [1, 3]

      assert %{change: [%{rows: removed}]} =
               ChangeAttendance.plan(:remove, [{jordan, "attending"}], rows)

      assert length(removed) == 3

      # Attended marks the one row the tab shows.
      shown = [row(jordan, 2, "absent"), row(jordan, 3, "requested")]

      assert %{change: [%{rows: [%{id: 2}]}]} =
               ChangeAttendance.plan(:attended, [{jordan, "absent"}], shown)
    end

    test "a member whose row changed since the tab loaded is left out, and one with none" do
      eli = member(1)
      quinn = member(2)

      assert ChangeAttendance.plan(
               :absent,
               [{eli, "requested"}, {quinn, "requested"}],
               [row(eli, 1, "attending")]
             ) == %{change: [], not_changed: [{eli, :changed}, {quinn, :gone}]}
    end

    test "Attended sends the activity's times; Absent sends no times" do
      sam = member(1)
      entries = [%{member: sam, rows: [row(sam, 1, "requested")]}]

      assert [%ChangeSetRow{action: :update_attendance, d4h_record_id: 901} = attended] =
               ChangeAttendance.rows(:attended, @activity, entries)

      assert attended.old_value["status"] == "requested"

      assert attended.new_value == %{
               "status" => "ATTENDING",
               "starts_at" => "2026-10-28T02:00:00Z",
               "ends_at" => "2026-10-28T04:30:00Z"
             }

      assert [%ChangeSetRow{new_value: %{"status" => "ABSENT"} = absent}] =
               ChangeAttendance.rows(:absent, @activity, entries)

      refute Map.has_key?(absent, "starts_at")

      assert [%ChangeSetRow{action: :delete_attendance, old_value: old}] =
               ChangeAttendance.rows(:remove, @activity, entries)

      assert old == %{"d4h_member_id" => 101, "status" => "requested"}
    end
  end

  test "result_text names each member not changed, and why (X1)" do
    casey = %Member{name: "Casey Dhillon"}

    assert ChangeAttendance.result_text(%{
             change: :absent,
             changed: [member(1), member(2), member(3)],
             not_changed: []
           }) == "3 members marked absent."

    assert ChangeAttendance.result_text(%{
             change: :remove,
             changed: [],
             not_changed: [{casey, :changed}]
           }) ==
             "Nobody was changed. Casey Dhillon was not changed: their attendance changed since the page loaded. Check it and try again."
  end

  test "open?/2: from the start until it's published, on one not deleted" do
    now = ~U[2026-10-28 03:00:00Z]
    refute ChangeAttendance.open?(@activity, ~U[2026-10-28 01:59:00Z])
    assert ChangeAttendance.open?(@activity, now)
    assert ChangeAttendance.open?(@activity, ~U[2026-11-28 03:00:00Z])
    refute ChangeAttendance.open?(%{@activity | is_published: true}, now)
    refute ChangeAttendance.open?(%{@activity | deleted_at: now}, now)
  end

  describe "call/6" do
    setup do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
      now = DateTime.utc_now()
      starts = now |> DateTime.add(-3, :hour) |> DateTime.truncate(:second)
      finishes = DateTime.add(starts, 150, :minute)
      activity = activity_fixture(team, %{started_at: starts, finished_at: finishes})

      casey = member_fixture(team, %{name: "Casey Dhillon"})
      riley = member_fixture(team, %{name: "Riley Okafor"})
      sam = member_fixture(team, %{name: "Sam Rivera"})

      rows = %{
        casey: attendance_fixture(activity, casey, %{status: "attending", started_at: starts}),
        riley: attendance_fixture(activity, riley, %{status: "requested"}),
        sam: attendance_fixture(activity, sam, %{status: "absent"})
      }

      %{
        user: user,
        team: team,
        activity: activity,
        casey: casey,
        riley: riley,
        sam: sam,
        rows: rows,
        now: now
      }
    end

    defp checked(ctx, names), do: for({name, status} <- names, do: {ctx[name].id, status})

    test "Absent writes D4H and the copy, as one change set of its own", ctx do
      ctx.rows |> Map.values() |> AttendanceStub.stub()
      checked = checked(ctx, casey: "attending", riley: "requested", sam: "absent")

      assert {:ok, result} =
               ChangeAttendance.call(ctx.team, ctx.activity, checked, :absent, ctx.user, ctx.now)

      assert Enum.map(result.changed, & &1.name) == ["Casey Dhillon", "Riley Okafor"]
      assert result.not_changed == []
      assert ChangeAttendance.result_text(result) == "2 members marked absent."

      for name <- [:casey, :riley] do
        id = ctx.rows[name].d4h_attendance_id
        assert_received {:d4h_write, ^id, %{"status" => "ABSENT"}}
      end

      refute_received {:d4h_write, _, _}
      assert Attendance |> Repo.all() |> Enum.map(& &1.status) |> Enum.uniq() == ["absent"]
      assert [%ChangeSet{source: :change_attendance}] = Repo.all(ChangeSet)
      refute_received {:email, _}

      # Send attendance's review leaves them out until they scan again.
      changed = SendAttendanceToD4H.changed_by_hand(ctx.activity)
      assert changed |> Map.keys() |> Enum.sort() == Enum.sort([ctx.casey.id, ctx.riley.id])
    end

    test "Attended uses the activity's times and clears a no-show", ctx do
      ctx.rows |> Map.values() |> AttendanceStub.stub()
      NoShow.record!(ctx.activity, ctx.sam)

      assert {:ok, %{changed: [_sam]}} =
               ChangeAttendance.call(
                 ctx.team,
                 ctx.activity,
                 checked(ctx, sam: "absent"),
                 :attended,
                 ctx.user,
                 ctx.now
               )

      id = ctx.rows.sam.d4h_attendance_id
      assert_received {:d4h_write, ^id, %{"status" => "ATTENDING"}}

      copy = Repo.get_by!(Attendance, member_id: ctx.sam.id)
      assert copy.status == "attending"
      assert copy.started_at == ctx.activity.started_at
      assert copy.duration_in_minutes == 150
      assert Repo.all(NoShow) == []
    end

    test "Remove deletes the rows from D4H and the copy", ctx do
      ctx.rows |> Map.values() |> AttendanceStub.stub()

      assert {:ok, %{changed: [_riley]}} =
               ChangeAttendance.call(
                 ctx.team,
                 ctx.activity,
                 checked(ctx, riley: "requested"),
                 :remove,
                 ctx.user,
                 ctx.now
               )

      id = ctx.rows.riley.d4h_attendance_id
      assert_received {:d4h_write, :delete, ^id}
      refute Repo.get_by(Attendance, member_id: ctx.riley.id)
    end

    test "a member D4H changed since is skipped and named", ctx do
      # D4H has Riley as attending now.
      AttendanceStub.stub([ctx.rows.casey, %{ctx.rows.riley | status: "attending"}])

      assert {:ok, %{changed: [], not_changed: [{%Member{name: "Riley Okafor"}, :changed}]}} =
               ChangeAttendance.call(
                 ctx.team,
                 ctx.activity,
                 checked(ctx, riley: "requested"),
                 :absent,
                 ctx.user,
                 ctx.now
               )

      assert Repo.get_by!(Attendance, member_id: ctx.riley.id).status == "requested"
    end

    test "refuses nobody it changes, and an activity that can't change", ctx do
      earlier = DateTime.add(ctx.activity.started_at, -1, :minute)
      casey = checked(ctx, casey: "attending")
      call = &ChangeAttendance.call(ctx.team, &1, &2, &3, ctx.user, &4)

      assert {:error, :none_selected} = call.(ctx.activity, casey, :attended, ctx.now)
      assert {:error, :none_selected} = call.(ctx.activity, [], :remove, ctx.now)
      assert {:error, :not_started} = call.(ctx.activity, casey, :absent, earlier)

      assert {:error, :deleted} =
               call.(%{ctx.activity | deleted_at: ctx.now}, casey, :absent, ctx.now)

      assert {:error, :published} =
               call.(%{ctx.activity | is_published: true}, casey, :absent, ctx.now)

      assert ChangeAttendance.error_text(ctx.team, :published) ==
               "Nobody was changed. Attendance cannot be changed once the activity is published. Unpublish it with Change activity first."

      assert Repo.all(ChangeSet) == []
    end

    test "a member of another team is never changed", ctx do
      other = member_fixture(team_fixture())

      assert {:error, :none_selected} =
               ChangeAttendance.call(
                 ctx.team,
                 ctx.activity,
                 [{other.id, "requested"}],
                 :absent,
                 ctx.user,
                 ctx.now
               )
    end
  end
end
