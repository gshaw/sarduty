defmodule App.Worker.SyncTeamChangesWorkerTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Attendance
  alias App.Model.Team
  alias App.Operation.SyncD4HChanges
  alias App.Worker.SyncTeamChangesWorker

  @newest "2026-10-05T12:00:00Z"
  @lists ~w(members tags exercises events incidents attendance member-qualifications
            member-qualification-awards member-groups member-group-memberships)

  defp head(total, newest \\ @newest),
    do: %{"results" => [%{"updatedAt" => newest}], "totalSize" => total}

  # A team whose last look saw every list at 10 rows, newest change @newest.
  defp synced_team do
    team = team_fixture(%{d4h_access_key: "team-key"})
    {:ok, at, 0} = DateTime.from_iso8601(@newest)
    heads = Map.new(@lists, &{&1, %{total_size: 10, newest_updated_at: at}})
    SyncD4HChanges.save_heads(team, heads, DateTime.utc_now())
  end

  defp perform(team), do: SyncTeamChangesWorker.perform(%Oban.Job{args: %{"team_id" => team.id}})

  defp list_name(conn), do: conn.path_info |> List.last()

  test "when nothing changed, a sync makes only the 10 list checks" do
    team = synced_team()
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      send(test, {:d4h, conn.request_path})
      Req.Test.json(conn, head(10))
    end)

    Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")
    assert perform(team) == :ok

    requests = for _ <- 1..10, do: assert_receive({:d4h, path})
    assert length(requests) == 10
    refute_received {:d4h, _}
    refute_received {:team_refreshed, _}
    assert Repo.reload(team).d4h_synced_at
  end

  test "drops an attendance row D4H deleted, found through its activity" do
    team = synced_team()
    member = member_fixture(team)
    activity = activity_fixture(team)
    kept = attendance_fixture(activity, member, %{status: "attending"})
    deleted = attendance_fixture(activity, member)

    row = %{
      "id" => kept.d4h_attendance_id,
      "activity" => %{"resourceType" => "Exercise", "id" => activity.d4h_activity_id},
      "member" => %{"resourceType" => "Member", "id" => member.d4h_member_id},
      "startsAt" => "2026-10-05T10:00:00Z",
      "endsAt" => "2026-10-05T12:00:00Z",
      "duration" => 120,
      "status" => "ABSENT",
      "updatedAt" => "2026-10-06T09:00:00Z"
    }

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      params = conn.query_params

      cond do
        list_name(conn) != "attendance" ->
          Req.Test.json(conn, head(10))

        params["size"] == "1" ->
          Req.Test.json(conn, head(1, "2026-10-06T09:00:00Z"))

        params["activity_id"] ->
          Req.Test.json(conn, %{"results" => [row], "totalSize" => 1})

        params["sort"] == "updatedAt" ->
          Req.Test.json(conn, %{"results" => [row], "totalSize" => 1})
      end
    end)

    Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")
    assert perform(team) == :ok

    assert Repo.get(Attendance, kept.id).status == "absent"
    refute Repo.get(Attendance, deleted.id)
    assert_received {:team_refreshed, %Team{}}
  end

  test "marks an activity D4H deleted, by comparing the ids it lists" do
    team = synced_team()
    deleted = activity_fixture(team, %{activity_kind: "event"})
    kept = activity_fixture(team, %{activity_kind: "event"})

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      params = conn.query_params

      cond do
        list_name(conn) != "events" and params["size"] == "1" ->
          Req.Test.json(conn, head(10))

        list_name(conn) != "events" ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        params["size"] == "1" ->
          Req.Test.json(conn, head(9))

        params["updated_after"] ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        true ->
          Req.Test.json(conn, %{"results" => [%{"id" => kept.d4h_activity_id}], "totalSize" => 1})
      end
    end)

    assert perform(team) == :ok

    assert Repo.reload(deleted).deleted_at
    refute Repo.reload(kept).deleted_at
  end

  test "skips a team whose full refresh is running" do
    team = synced_team()
    {:ok, team} = Team.update(team, %{d4h_refresh_result: "Members: 10/100 (10%)"})

    assert {:cancel, _} = perform(team)
  end

  test "a team synced over 2 minutes ago is stale, one without a key never is" do
    now = ~U[2026-10-06 12:00:00Z]
    team = %Team{d4h_team_id: 1, d4h_access_key: "key", d4h_synced_at: ~U[2026-10-06 11:57:00Z]}

    assert SyncTeamChangesWorker.stale?(team, now)
    refute SyncTeamChangesWorker.stale?(%{team | d4h_synced_at: ~U[2026-10-06 11:59:00Z]}, now)
    assert SyncTeamChangesWorker.stale?(%{team | d4h_synced_at: nil}, now)
    refute SyncTeamChangesWorker.stale?(%{team | d4h_access_key: nil}, now)
  end

  test "a rejected key stops the syncs until a new key or a refresh" do
    team = synced_team()
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 401, ""))

    assert {:cancel, _} = perform(team)
    team = Repo.reload(team)
    assert SyncD4HChanges.key_rejected?(team)
    refute SyncTeamChangesWorker.syncs?(team)
    refute SyncTeamChangesWorker.stale?(team, DateTime.add(DateTime.utc_now(), 1, :hour))

    team =
      SyncD4HChanges.save_heads(team, SyncD4HChanges.previous_heads(team), DateTime.utc_now())

    assert SyncTeamChangesWorker.syncs?(team)
  end

  test "a failing sync tells Honeybadger only after an hour, and once" do
    team = synced_team()
    start = ~U[2026-10-06 12:00:00Z]

    assert {team, false} = SyncD4HChanges.record_failure(team, start)
    assert {team, false} = SyncD4HChanges.record_failure(team, DateTime.add(start, 50, :minute))
    assert {team, true} = SyncD4HChanges.record_failure(team, DateTime.add(start, 60, :minute))
    assert {_team, false} = SyncD4HChanges.record_failure(team, DateTime.add(start, 70, :minute))
  end
end
