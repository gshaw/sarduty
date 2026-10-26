defmodule App.Operation.InviteMembersTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AttendanceStub
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.Group
  alias App.Model.Member
  alias App.Operation.InviteMembers

  @now ~U[2026-10-19 12:00:00Z]
  @starts ~U[2026-10-20 18:00:00Z]
  @ends ~U[2026-10-20 21:00:00Z]

  defp activity, do: %Activity{d4h_activity_id: 900, started_at: @starts, finished_at: @ends}

  defp member(id, attrs \\ %{}),
    do: struct(%Member{id: id, d4h_member_id: 100 + id, name: "Member #{id}"}, attrs)

  defp known(attrs \\ %{}), do: Map.merge(%{on_activity: [], away: [], now: @now}, attrs)

  defp added(plan), do: Enum.map(plan.add, fn {reason, m} -> {m.id, reason} end)

  @boats %Group{title: "Boat Operators"}
  @rope %Group{title: "Rope"}

  test "each member goes as requested, for the activity's times" do
    plan = InviteMembers.plan(activity(), [{@boats, member(1)}], known())

    assert [row] = InviteMembers.rows(activity(), plan.add)
    assert row.action == :create_attendance
    assert row.member_id == 1
    assert row.reason == "In the Boat Operators group"

    assert row.new_value == %{
             "d4h_activity_id" => 900,
             "d4h_member_id" => 101,
             "status" => "REQUESTED",
             "starts_at" => "2026-10-20T18:00:00Z",
             "ends_at" => "2026-10-20T21:00:00Z"
           }
  end

  test "by name, by group, and both" do
    picks = [{:name, member(1)}, {@boats, member(2)}, {@boats, member(3)}]
    plan = InviteMembers.plan(activity(), picks, known())

    assert added(plan) == [{1, :name}, {2, @boats}, {3, @boats}]

    rows = InviteMembers.rows(activity(), plan.add)

    assert Enum.map(rows, & &1.reason) == [
             "Added by name",
             "In the Boat Operators group",
             "In the Boat Operators group"
           ]
  end

  test "a member in two groups goes once, with the first reason" do
    picks = [{@boats, member(1)}, {@rope, member(1)}, {@rope, member(2)}]
    assert added(InviteMembers.plan(activity(), picks, known())) == [{1, @boats}, {2, @rope}]
  end

  # D4H would add a second row for them.
  test "a member on the activity already is left out and named" do
    picks = [{@boats, member(1)}, {@boats, member(2, name: "Dana Clark")}]
    plan = InviteMembers.plan(activity(), picks, known(%{on_activity: [2]}))

    assert added(plan) == [{1, @boats}]
    assert Enum.map(plan.on_activity, & &1.name) == ["Dana Clark"]
  end

  test "away on the day leaves out a group's member, not one added by name" do
    picks = [
      {@boats, member(1, name: "Jo Park")},
      {@boats, member(2)},
      {:name, member(3)},
      {@rope, member(4)},
      {:name, member(4)}
    ]

    plan = InviteMembers.plan(activity(), picks, known(%{away: [1, 3, 4]}))

    assert added(plan) == [{2, @boats}, {3, :name}, {4, :name}]
    assert Enum.map(plan.away, & &1.name) == ["Jo Park"]
  end

  test "retired members and members marked not a person are left out, unnamed" do
    picks = [
      {@boats, member(1, d4h_status: "RETIRED")},
      {:name, member(2, left_at: ~U[2026-01-01 00:00:00Z])},
      {@boats, member(3, not_a_person: true)},
      {@boats, member(4)}
    ]

    plan = InviteMembers.plan(activity(), picks, known(%{on_activity: [1], away: [3]}))

    assert added(plan) == [{4, @boats}]
    assert plan.on_activity == []
    assert plan.away == []
  end

  describe "call/6" do
    setup do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
      now = DateTime.utc_now()
      starts = now |> DateTime.add(3, :day) |> DateTime.truncate(:second)

      activity =
        activity_fixture(team, %{started_at: starts, finished_at: DateTime.add(starts, 3, :hour)})

      eli = member_fixture(team, %{name: "Eli Haddad"})
      wren = member_fixture(team, %{name: "Wren Adams"})
      sam = member_fixture(team, %{name: "Sam Rivera"})
      %{user: user, team: team, activity: activity, eli: eli, wren: wren, sam: sam, now: now}
    end

    # D4H has Sam on the activity now, which the copy has not seen, and refuses Wren.
    defp stub_d4h(ctx) do
      sam = %Attendance{
        d4h_attendance_id: 77,
        member_id: ctx.sam.id,
        member: ctx.sam,
        activity_id: ctx.activity.id,
        activity: ctx.activity,
        status: "requested",
        started_at: ctx.activity.started_at,
        finished_at: ctx.activity.finished_at
      }

      AttendanceStub.stub([sam], refuse: [ctx.wren.d4h_member_id])
    end

    test "the copy gets only the rows D4H took", ctx do
      stub_d4h(ctx)
      picks = [{:name, ctx.eli}, {:name, ctx.wren}, {:name, ctx.sam}]

      assert {:ok, %{rows: rows}} =
               InviteMembers.call(ctx.team, ctx.activity, picks, ctx.user, :invite, ctx.now)

      assert Enum.map(rows, &{&1.member_id, &1.status}) == [
               {ctx.eli.id, :applied},
               {ctx.wren.id, :failed},
               {ctx.sam.id, :skipped}
             ]

      assert_received {:d4h_write, :create, %{"status" => "REQUESTED"}}

      assert [%Attendance{status: "requested", d4h_attendance_id: d4h_id} = copy] =
               Repo.all(Attendance)

      assert copy.member_id == ctx.eli.id
      assert d4h_id == hd(rows).d4h_record_id
      assert copy.started_at == ctx.activity.started_at
      assert copy.duration_in_minutes == 180
      assert [%ChangeSet{source: :invite}] = Repo.all(ChangeSet)
    end

    test "refuses an activity that has started, is deleted, or is published", ctx do
      picks = [{:name, ctx.eli}]
      later = DateTime.add(ctx.activity.started_at, 1, :minute)
      deleted = %{ctx.activity | deleted_at: ctx.now}
      published = %{ctx.activity | is_published: true}

      assert {:error, :started} =
               InviteMembers.call(ctx.team, ctx.activity, picks, ctx.user, :invite, later)

      assert {:error, :deleted} =
               InviteMembers.call(ctx.team, deleted, picks, ctx.user, :invite, ctx.now)

      assert {:error, :published} =
               InviteMembers.call(ctx.team, published, picks, ctx.user, :invite, ctx.now)

      assert InviteMembers.error_text(ctx.team, :published) ==
               "Nobody was added. Attendance cannot be changed once the activity is published. Unpublish it in D4H first."

      assert Repo.all(ChangeSet) == []
    end

    test "a member of another team is never added", ctx do
      other = member_fixture(team_fixture())

      assert {:ok, %{rows: []}} =
               InviteMembers.call(
                 ctx.team,
                 ctx.activity,
                 [{:name, other}],
                 ctx.user,
                 :invite,
                 ctx.now
               )
    end
  end
end
