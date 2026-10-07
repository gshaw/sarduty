defmodule App.Operation.ApplyAttendanceImportTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Operation.ApplyAttendanceImport

  # A pasted report says Mei came and Sam didn't. Between the paste and the click,
  # someone marked Lena attending in D4H by hand.
  setup do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    activity = activity_fixture(team)
    mei = member_fixture(team, %{name: "Mei Chen"})
    sam = member_fixture(team, %{name: "Sam Ortiz"})
    lena = member_fixture(team, %{name: "Lena Park"})
    %{user: user, team: team, activity: activity, mei: mei, sam: sam, lena: lena}
  end

  defp row(ctx, id, member, status) do
    %{
      "id" => id,
      "activity" => %{"resourceType" => "Exercise", "id" => ctx.activity.d4h_activity_id},
      "member" => %{"resourceType" => "Member", "id" => member.d4h_member_id},
      "status" => status,
      "startsAt" => DateTime.to_iso8601(ctx.activity.started_at),
      "endsAt" => DateTime.to_iso8601(ctx.activity.finished_at)
    }
  end

  defp stub_d4h(ctx, published \\ false) do
    test_pid = self()

    rows = [
      row(ctx, 501, ctx.mei, "REQUESTED"),
      row(ctx, 502, ctx.sam, "ATTENDING"),
      row(ctx, 503, ctx.lena, "ATTENDING")
    ]

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")

      case {conn.method, path} do
        {"GET", "/exercises/" <> _} ->
          Req.Test.json(conn, %{"published" => published})

        {"GET", "/attendance"} ->
          Req.Test.json(conn, %{"results" => rows, "totalSize" => length(rows)})

        {"PATCH", "/attendance/" <> id} ->
          send(test_pid, {:d4h_write, id, Jason.decode!(body)})
          Req.Test.json(conn, written_row(ctx, id, Jason.decode!(body)))
      end
    end)
  end

  defp written_row(ctx, id, json) do
    member = if id == "501", do: ctx.mei, else: ctx.sam
    row(ctx, String.to_integer(id), member, json["status"])
  end

  defp changes(ctx) do
    [
      %{
        action: :add,
        d4h_attendance_id: 501,
        d4h_member_id: ctx.mei.d4h_member_id,
        status: "requested"
      },
      %{
        action: :remove,
        d4h_attendance_id: 502,
        d4h_member_id: ctx.sam.d4h_member_id,
        status: "attending"
      },
      %{
        action: :add,
        d4h_attendance_id: 503,
        d4h_member_id: ctx.lena.d4h_member_id,
        status: "requested"
      }
    ]
  end

  test "sends each change, skips one D4H changed since, and records them all", ctx do
    stub_d4h(ctx)
    now = DateTime.utc_now()

    assert {:ok, results} =
             ApplyAttendanceImport.call(ctx.team, ctx.activity, ctx.user, changes(ctx), now)

    assert_received {:d4h_write, "501", %{"status" => "ATTENDING"} = mei}
    refute Map.has_key?(mei, "startsAt")
    assert_received {:d4h_write, "502", %{"status" => "ABSENT"}}
    refute_received {:d4h_write, "503", _}

    assert [:applied, :applied, :skipped] = Enum.map(results, fn {_change, row} -> row.status end)

    [change_set] = Repo.all(ChangeSet)
    assert change_set.source == :attendance_import
    assert change_set.applied_by_user_id == ctx.user.id
    assert change_set.applied_at

    mei_id = ctx.mei.id

    assert [
             %ChangeSetRow{member_id: ^mei_id, status: :applied, d4h_record_id: 501},
             %ChangeSetRow{status: :applied, new_value: %{"status" => "ABSENT"}},
             %ChangeSetRow{
               status: :skipped,
               error: "D4H changed this since the review. Review again."
             }
           ] = ChangeSetRow |> order_by(:id) |> Repo.all()
  end

  test "a published activity gets no writes", ctx do
    stub_d4h(ctx, true)

    assert {:error, :published} =
             ApplyAttendanceImport.call(
               ctx.team,
               ctx.activity,
               ctx.user,
               changes(ctx),
               DateTime.utc_now()
             )

    refute_received {:d4h_write, _, _}
    assert Repo.aggregate(ChangeSetRow, :count) == 3
    refute Repo.one(ChangeSet).applied_at
  end
end
