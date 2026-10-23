defmodule App.Operation.ReplyToActivityTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Operation.ReplyToActivity

  @start ~U[2026-10-29 02:00:00Z]
  @finish ~U[2026-10-29 05:00:00Z]
  @before ~U[2026-10-26 16:00:00Z]

  defp activity(attrs \\ %{}),
    do: struct(%Activity{id: 7, started_at: @start, finished_at: @finish}, attrs)

  # D4H gives every invited member a requested row until they reply.
  defp invitation(attrs \\ %{}) do
    struct(
      %Attendance{
        member_id: 3,
        d4h_attendance_id: 501,
        status: "requested",
        started_at: @start,
        finished_at: @finish
      },
      attrs
    )
  end

  test "I'll be there marks the member's row attending with the activity's times" do
    # Morgan's own times in D4H give way to the activity's.
    row = invitation(%{started_at: ~U[2026-10-29 03:00:00Z]})

    assert {:ok, %ChangeSetRow{} = change} =
             ReplyToActivity.plan(activity(), row, :yes, @before)

    assert change.action == :update_attendance
    assert change.d4h_record_id == 501
    assert change.member_id == 3

    assert change.new_value == %{
             "status" => "ATTENDING",
             "starts_at" => "2026-10-29T02:00:00Z",
             "ends_at" => "2026-10-29T05:00:00Z"
           }

    assert change.old_value["status"] == "requested"
    assert change.old_value["starts_at"] == "2026-10-29T03:00:00Z"
  end

  test "Can't make it marks the member's row absent" do
    assert {:ok, change} = ReplyToActivity.plan(activity(), invitation(), :no, @before)

    assert change.action == :update_attendance
    assert change.new_value == %{"status" => "ABSENT"}
  end

  test "a member can change their reply until the start" do
    signed_up = invitation(%{status: "attending"})
    assert {:ok, change} = ReplyToActivity.plan(activity(), signed_up, :no, @before)
    assert change.old_value["status"] == "attending"

    cant = invitation(%{status: "absent"})
    assert {:ok, change} = ReplyToActivity.plan(activity(), cant, :yes, @before)
    assert change.new_value["status"] == "ATTENDING"
  end

  test "replies close when the activity starts" do
    assert ReplyToActivity.plan(activity(), invitation(), :yes, @start) == {:error, :started}

    assert ReplyToActivity.plan(activity(), invitation(), :no, DateTime.add(@start, 60)) ==
             {:error, :started}

    assert {:ok, _} =
             ReplyToActivity.plan(activity(), invitation(), :yes, DateTime.add(@start, -1))
  end

  # Being invited means D4H has the row, so a reply never adds one.
  test "a member with no row is not invited, and nothing is created" do
    assert ReplyToActivity.plan(activity(), nil, :yes, @before) == {:error, :not_invited}
    assert ReplyToActivity.plan(activity(), nil, :no, @before) == {:error, :not_invited}
  end

  test "an activity deleted in D4H takes no replies" do
    deleted = activity(%{deleted_at: ~U[2026-10-25 00:00:00Z]})
    assert ReplyToActivity.plan(deleted, invitation(), :yes, @before) == {:error, :deleted}
  end

  describe "call/6, against a stubbed D4H" do
    setup do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
      now = DateTime.utc_now()
      start = now |> DateTime.add(3, :day) |> DateTime.truncate(:second)

      activity =
        activity_fixture(team, %{started_at: start, finished_at: DateTime.add(start, 3, :hour)})

      member = member_fixture(team, %{name: "Sam Rivera"})
      row = attendance_fixture(activity, member, %{status: "requested", d4h_attendance_id: 501})
      %{user: user, team: team, activity: activity, member: member, row: row, now: now}
    end

    # D4H has the row, and someone marked it absent there since the copy was made.
    defp stub_d4h(ctx, published \\ false) do
      test_pid = self()

      d4h_row = %{
        "id" => 501,
        "activity" => %{"resourceType" => "Exercise", "id" => ctx.activity.d4h_activity_id},
        "member" => %{"resourceType" => "Member", "id" => ctx.member.d4h_member_id},
        "status" => "ABSENT",
        "startsAt" => DateTime.to_iso8601(ctx.activity.started_at),
        "endsAt" => DateTime.to_iso8601(ctx.activity.finished_at)
      }

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")

        case {conn.method, path} do
          {"GET", "/exercises/" <> _} ->
            Req.Test.json(conn, %{"published" => published})

          {"GET", "/attendance"} ->
            Req.Test.json(conn, %{"results" => [d4h_row], "totalSize" => 1})

          {"PATCH", "/attendance/501"} ->
            send(test_pid, {:d4h_write, Jason.decode!(body)})
            Req.Test.json(conn, %{d4h_row | "status" => "ATTENDING"})
        end
      end)
    end

    test "the latest tap wins over D4H's status, and the copy updates at once", ctx do
      stub_d4h(ctx)

      assert {:ok, saved} =
               ReplyToActivity.call(ctx.team, ctx.activity, ctx.member, :yes, ctx.user, ctx.now)

      assert_received {:d4h_write, %{"status" => "ATTENDING", "startsAt" => _, "endsAt" => _}}
      assert saved.id == ctx.row.id
      assert saved.status == "attending"
      assert saved.replied_at == DateTime.truncate(ctx.now, :second)
      assert saved.started_at == ctx.activity.started_at
      assert saved.duration_in_minutes == 180

      assert [%ChangeSet{source: :member, activity_id: activity_id}] = Repo.all(ChangeSet)
      assert activity_id == ctx.activity.id
    end

    test "a published activity takes no reply, and the copy stays", ctx do
      stub_d4h(ctx, true)

      assert {:error, "Your reply cannot be sent. D4H has published this activity."} =
               ReplyToActivity.call(ctx.team, ctx.activity, ctx.member, :no, ctx.user, ctx.now)

      refute_received {:d4h_write, _}
      assert Repo.reload(ctx.row).status == "requested"
    end

    test "a member who is not invited gets an answer, and D4H is never called", ctx do
      outsider = member_fixture(ctx.team)

      assert {:error, "Only members invited in D4H can reply."} =
               ReplyToActivity.call(ctx.team, ctx.activity, outsider, :yes, ctx.user, ctx.now)

      assert Repo.all(ChangeSet) == []
    end
  end
end
