defmodule App.Operation.ApplyProposedChangeSetTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.ChangeSet
  alias App.Operation.ApplyProposedChangeSet
  alias App.Operation.ProposeAttendanceChanges

  setup do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    activity = activity_fixture(team)
    mei = member_fixture(team, %{name: "Mei Chen"})
    sam = member_fixture(team, %{name: "Sam Ortiz"})
    attendance_fixture(activity, sam, %{status: "absent", d4h_attendance_id: 502})
    %{user: user, team: team, activity: activity, mei: mei, sam: sam}
  end

  defp propose(ctx) do
    requests = [
      %{"member_id" => ctx.mei.id, "status" => "attended"},
      %{"member_id" => ctx.sam.id, "status" => "attended"}
    ]

    {:ok, change_set, []} =
      ProposeAttendanceChanges.call(
        ctx.team,
        ctx.user,
        ctx.activity.id,
        requests,
        "Sheet",
        DateTime.utc_now()
      )

    ChangeSet.find!(ctx.team, change_set.id)
  end

  defp stub_d4h(ctx, published) do
    test_pid = self()

    sam_row = %{
      "id" => 502,
      "activity" => %{"resourceType" => "Exercise", "id" => ctx.activity.d4h_activity_id},
      "member" => %{"resourceType" => "Member", "id" => ctx.sam.d4h_member_id},
      "status" => "ABSENT",
      "startsAt" => DateTime.to_iso8601(ctx.activity.started_at),
      "endsAt" => DateTime.to_iso8601(ctx.activity.finished_at)
    }

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")

      respond(conn, {conn.method, path}, body, %{
        ctx: ctx,
        pid: test_pid,
        row: sam_row,
        published: published
      })
    end)
  end

  # D4H's answers, one clause per call the sends make. `s` holds the test's pid, the
  # activity, Sam's row, and whether D4H says the activity is published.
  defp respond(conn, {"GET", "/exercises/" <> _id}, _body, s),
    do: Req.Test.json(conn, %{"published" => s.published})

  defp respond(conn, {"GET", "/attendance"}, _body, s),
    do: Req.Test.json(conn, %{"results" => [s.row], "totalSize" => 1})

  defp respond(conn, {"POST", "/exercises/" <> rest}, body, s) do
    send(s.pid, {:d4h_publish, rest, Jason.decode!(body)["published"]})
    Req.Test.json(conn, %{"id" => s.ctx.activity.d4h_activity_id})
  end

  defp respond(conn, {"POST", "/attendance"}, body, s) do
    send(s.pid, {:d4h_create, Jason.decode!(body)})
    Req.Test.json(conn, %{s.row | "id" => 503, "status" => "ATTENDING"})
  end

  defp respond(conn, {"DELETE", "/attendance/502"}, _body, s) do
    send(s.pid, {:d4h_delete, 502})
    Plug.Conn.send_resp(conn, 204, "")
  end

  defp respond(conn, {"PATCH", "/attendance/502"}, body, s) do
    send(s.pid, {:d4h_write, Jason.decode!(body)})
    Req.Test.json(conn, %{s.row | "status" => "ATTENDING"})
  end

  test "an agent's set waits; nothing is sent to D4H until a team admin applies it", ctx do
    change_set = propose(ctx)

    assert change_set.source == :agent
    assert change_set.summary == "Sheet"
    assert ChangeSet.waiting?(change_set)
    assert ChangeSet.count_waiting(ctx.team.id) == 1
    assert ChangeSet.count_waiting(team_fixture().id) == 0
  end

  test "sends the ticked rows and skips the rest", ctx do
    change_set = propose(ctx)
    stub_d4h(ctx, false)
    sam_row = Enum.find(change_set.rows, &(&1.member_id == ctx.sam.id))

    {:ok, rows} =
      ApplyProposedChangeSet.call(
        ctx.team,
        change_set,
        ctx.user,
        [sam_row.id],
        DateTime.utc_now()
      )

    assert_received {:d4h_write, %{"status" => "ATTENDING"}}
    refute_received {:d4h_write, _}
    assert Enum.map(rows, & &1.status) == [:applied]

    change_set = ChangeSet.find!(ctx.team, change_set.id)
    refute ChangeSet.waiting?(change_set)

    assert change_set.rows |> Enum.map(&{&1.member_id, &1.status}) |> Enum.sort() ==
             Enum.sort([{ctx.mei.id, :skipped}, {ctx.sam.id, :applied}])
  end

  test "a published activity sends nothing and leaves every row waiting", ctx do
    change_set = propose(ctx)
    stub_d4h(ctx, true)
    ids = [hd(change_set.rows).id]

    assert ApplyProposedChangeSet.call(ctx.team, change_set, ctx.user, ids, DateTime.utc_now()) ==
             {:error, :published}

    change_set = ChangeSet.find!(ctx.team, change_set.id)
    assert ChangeSet.waiting?(change_set)
    assert Enum.all?(change_set.rows, &(&1.status == :proposed))
  end

  test "a discarded set can't be sent", ctx do
    change_set = ctx |> propose() |> ChangeSet.discard!(DateTime.utc_now())
    ids = Enum.map(change_set.rows, & &1.id)

    assert ApplyProposedChangeSet.call(ctx.team, change_set, ctx.user, ids, DateTime.utc_now()) ==
             {:error, :decided}
  end

  test "another team's activity can't be proposed to", ctx do
    other = activity_fixture(team_fixture())

    assert ProposeAttendanceChanges.call(
             ctx.team,
             ctx.user,
             other.id,
             [],
             nil,
             DateTime.utc_now()
           ) ==
             {:error, ["No activity #{other.id} on this team."]}
  end

  test "a remove takes the row off D4H, and out of SAR Duty's copy at once", ctx do
    [row] = App.Repo.all(App.Model.Attendance)

    {:ok, change_set, []} =
      ProposeAttendanceChanges.call(
        ctx.team,
        ctx.user,
        ctx.activity.id,
        [%{"attendance_id" => row.id, "status" => "remove", "reason" => "Duplicate"}],
        "Duplicates",
        DateTime.utc_now()
      )

    change_set = ChangeSet.find!(ctx.team, change_set.id)
    stub_d4h(ctx, false)
    ids = Enum.map(change_set.rows, & &1.id)

    {:ok, [applied]} =
      ApplyProposedChangeSet.call(ctx.team, change_set, ctx.user, ids, DateTime.utc_now())

    assert applied.status == :applied
    assert_received {:d4h_delete, 502}
    assert App.Repo.all(App.Model.Attendance) == []
  end

  describe "a published activity" do
    setup ctx do
      activity = ctx.activity |> Ecto.Changeset.change(is_published: true) |> App.Repo.update!()
      %{activity: activity}
    end

    test "is made a draft, changed, and published again", ctx do
      change_set = propose(ctx)
      assert [%{action: :publish_activity} | _rows] = change_set.rows
      stub_d4h(ctx, true)
      lines = for row <- change_set.rows, row.action != :publish_activity, do: row.id

      {:ok, rows} =
        ApplyProposedChangeSet.call(ctx.team, change_set, ctx.user, lines, DateTime.utc_now())

      assert Enum.all?(rows, &(&1.status == :applied)),
             inspect(Enum.map(rows, &{&1.action, &1.error}))

      assert_received {:d4h_publish, _path, false}
      assert_received {:d4h_write, _body}
      assert_received {:d4h_publish, _path, true}
    end

    test "found a draft when sending, it stays a draft", ctx do
      change_set = propose(ctx)
      stub_d4h(ctx, false)
      lines = for row <- change_set.rows, row.action != :publish_activity, do: row.id

      {:ok, rows} =
        ApplyProposedChangeSet.call(ctx.team, change_set, ctx.user, lines, DateTime.utc_now())

      [draft | _rest] = rows
      assert draft.status == :skipped
      assert List.last(rows).error == "Left as it was, a draft."
      refute_received {:d4h_publish, _path, _published}
    end
  end
end
