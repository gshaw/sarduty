defmodule App.Worker.SyncTeamChangesWorkerTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.Attendance
  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.SyncD4HChanges
  alias App.Worker.SyncTeamChangesWorker

  @newest "2026-10-05T12:00:00Z"
  @lists ~w(members tags exercises events incidents attendance member-qualifications
            member-qualification-awards award-documents member-groups
            member-group-memberships equipment equipment-usages)

  defp head(total, newest \\ @newest),
    do: %{"results" => [%{"updatedAt" => newest}], "totalSize" => total}

  # A team whose last look saw every list at 10 rows, newest change @newest.
  defp synced_team(attrs \\ %{}) do
    team = team_fixture(Map.merge(%{d4h_access_key: "team-key"}, attrs))
    {:ok, at, 0} = DateTime.from_iso8601(@newest)
    heads = Map.new(@lists, &{&1, %{total_size: 10, newest_updated_at: at}})
    SyncD4HChanges.save_heads(team, heads, DateTime.utc_now())
  end

  defp perform(team), do: SyncTeamChangesWorker.perform(%Oban.Job{args: %{"team_id" => team.id}})

  defp list_name(conn), do: conn.path_info |> List.last()

  test "when nothing changed, a sync makes the 13 list checks and reads the open years" do
    check_unchanged_sync(synced_team())
  end

  test "a SAR Duty Records team's sync reads the open years too" do
    check_unchanged_sync(synced_team(%{d4h_api_host: D4H.records_host()}))
  end

  # D4H answers every head unchanged and each open year's read empty, telling the test.
  defp stub_unchanged do
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      send(test, {:d4h, list_name(conn), conn.query_params})

      if conn.query_params["starts_after"],
        do: Req.Test.json(conn, %{"results" => [], "totalSize" => 0}),
        else: Req.Test.json(conn, head(10))
    end)
  end

  defp check_unchanged_sync(team) do
    stub_unchanged()
    Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")
    assert perform(team) == :ok

    requests = for _ <- 1..16, do: assert_receive({:d4h, _list, _params})
    open_years = for {:d4h, list, %{"starts_after" => _}} <- requests, do: list
    assert Enum.sort(open_years) == ~w(events exercises incidents)
    refute_received {:d4h, _, _}
    refute_received {:team_refreshed, _}
    assert Repo.reload(team).d4h_synced_at
    refute Event.get_last(:d4h_team_sync)
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
        params["starts_after"] ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

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
        params["starts_after"] ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

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

  # D4H answers with `activity` tagged `tags` in the open years' read, every head unchanged.
  defp stub_open_year(team, activity, tags) do
    d4h_activity = %{
      "id" => activity.d4h_activity_id,
      "resourceType" => "Exercise",
      "owner" => %{"resourceType" => "Team", "id" => team.d4h_team_id},
      "reference" => activity.ref_id,
      "referenceDescription" => activity.title,
      "published" => true,
      "startsAt" => DateTime.to_iso8601(activity.started_at),
      "endsAt" => DateTime.to_iso8601(activity.finished_at),
      "address" => %{},
      "tags" => for(tag <- tags, do: %{"resourceType" => "Tag", "id" => tag.d4h_tag_id})
    }

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case {list_name(conn), conn.query_params["starts_after"]} do
        {_list, nil} -> Req.Test.json(conn, head(10))
        {"exercises", _} -> Req.Test.json(conn, %{"results" => [d4h_activity], "totalSize" => 1})
        _other_kind -> Req.Test.json(conn, %{"results" => [], "totalSize" => 0})
      end
    end)
  end

  test "a tag changed in D4H reaches an open year's activity, though no head moved (#358)" do
    team = synced_team()
    primary = tag_fixture(team, "Primary Hours")

    activity =
      activity_fixture(team, %{started_at: DateTime.utc_now(), tags: [], is_published: true})

    stub_open_year(team, activity, [primary])

    Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")
    assert perform(team) == :ok

    assert Repo.reload(activity).tags == ["Primary Hours"]
    assert_received {:team_refreshed, %Team{}}
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

    assert %Event{team_id: team_id, data: %{"outcome" => "key_rejected", "status" => 401}} =
             Event.get_last(:d4h_team_sync)

    assert team_id == team.id
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
