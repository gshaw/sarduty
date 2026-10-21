defmodule App.Operation.SendChoreEventsTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.ChangeSet
  alias App.Model.Chore
  alias App.Model.ChoreCategoryTag
  alias App.Model.ChoreEvent
  alias App.Operation.SaveChore
  alias App.Operation.SendChoreEvents

  setup do
    %{user: user, team: team} =
      user_with_team_fixture(%{team: %{d4h_access_key: "team-key", member_logins: true}})

    hours = tag_fixture(team, "Primary Hours")
    other = tag_fixture(team, "Chores")
    category = chore_category_fixture(team)
    Repo.insert!(%ChoreCategoryTag{chore_category_id: category.id, tag_id: other.id})
    member = member_fixture(team, %{name: "Sam Rivera"})
    %{user: user, team: team, category: category, member: member, tags: [hours, other]}
  end

  defp event(id, published) do
    %{
      "id" => id,
      "resourceType" => "Event",
      "owner" => %{"resourceType" => "Team", "id" => 1},
      "referenceDescription" => "Chores",
      "published" => published,
      "startsAt" => "2026-10-31T07:00:00Z",
      "endsAt" => "2026-10-31T08:00:00Z",
      "tags" => []
    }
  end

  defp attendance(id, member, minutes) do
    %{
      "id" => id,
      "activity" => %{"resourceType" => "Event", "id" => 900},
      "member" => %{"resourceType" => "Member", "id" => member.d4h_member_id},
      "status" => "ATTENDING",
      "startsAt" => "2026-10-31T07:00:00Z",
      "endsAt" =>
        ~U[2026-10-31 07:00:00Z] |> DateTime.add(minutes, :minute) |> DateTime.to_iso8601()
    }
  end

  # D4H, sending each write to the test. `existing` is the attendance on event 900, and
  # `event_status` what reading the event answers.
  defp stub_d4h(existing \\ [], event_status \\ 200) do
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")
      json = if body == "", do: nil, else: Jason.decode!(body)
      if conn.method != "GET", do: send(test_pid, {:d4h, conn.method, path, json})
      answer(conn, conn.method, path, json, existing, event_status)
    end)
  end

  defp answer(conn, "GET", "/events/900", _json, _existing, 404),
    do: conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"title" => "Not Found"})

  defp answer(conn, "GET", "/events/" <> _id, _json, _existing, _status),
    do: Req.Test.json(conn, event(900, true))

  defp answer(conn, "GET", "/attendance", _json, existing, _status),
    do: Req.Test.json(conn, %{"results" => existing, "totalSize" => length(existing)})

  defp answer(conn, method, "/events" <> _rest, _json, _existing, _status)
       when method in ["POST", "PATCH"],
       do: Req.Test.json(conn, event(900, false))

  defp answer(conn, "POST", "/attendance", json, _existing, _status),
    do: Req.Test.json(conn, attendance(701, %{d4h_member_id: json["memberId"]}, 60))

  defp answer(conn, "PATCH", "/attendance/" <> id, _json, _existing, _status),
    do: Req.Test.json(conn, attendance(String.to_integer(id), %{d4h_member_id: 1}, 60))

  defp answer(conn, "DELETE", "/attendance/" <> _id, _json, _existing, _status),
    do: Plug.Conn.send_resp(conn, 204, "")

  defp writes do
    receive do
      {:d4h, method, path, json} -> [{method, path, json} | writes()]
    after
      0 -> []
    end
  end

  test "accepting a chore marks its event, and the send makes it in D4H", ctx do
    chore = chore_fixture(ctx.member, ctx.category, %{date: ~D[2026-10-06], minutes: 90})
    assert SaveChore.accept(ctx.team, [chore.id], ctx.user, DateTime.utc_now()) == 1

    [event] = ChoreEvent.get_to_send(ctx.team.id)
    assert event.month == ~D[2026-10-01]
    assert Repo.get!(Chore, chore.id).chore_event_id == event.id

    stub_d4h()
    assert SendChoreEvents.call(ctx.team, DateTime.utc_now()) == %{sent: 1, failed: 0}

    [create, tags, add, publish] = writes()

    assert {"POST", "/events", %{"fullTeam" => false, "startsAt" => "2026-10-31T07:00:00Z"}} =
             create

    assert {"POST", "/events/900/tags", %{"tagIds" => tag_ids}} = tags
    assert Enum.sort(tag_ids) == ctx.tags |> Enum.map(& &1.d4h_tag_id) |> Enum.sort()

    assert {"POST", "/attendance", %{"activityId" => 900, "endsAt" => "2026-10-31T08:30:00Z"}} =
             add

    assert {"POST", "/events/900/publish", %{"published" => true}} = publish

    assert %{needs_send: false, d4h_activity_id: 900, send_error: nil} =
             Repo.get!(ChoreEvent, event.id)

    [change_set] = Repo.all(ChangeSet)
    assert %{source: :chores, applied_by_user_id: nil} = change_set
  end

  test "declining an accepted chore sends the event again without the member", ctx do
    chore = chore_fixture(ctx.member, ctx.category, %{date: ~D[2026-10-06]})
    {:ok, chore} = SaveChore.accept_one(ctx.team, chore, ctx.user, DateTime.utc_now())
    event = Repo.get!(ChoreEvent, chore.chore_event_id)
    ChoreEvent.record_send!(event, 900, nil, DateTime.utc_now())

    {:ok, _chore} =
      SaveChore.decline(ctx.team, chore, "Not a chore.", ctx.user, DateTime.utc_now())

    assert Repo.get!(ChoreEvent, event.id).needs_send

    stub_d4h([attendance(701, ctx.member, 60)])
    assert SendChoreEvents.call(ctx.team, DateTime.utc_now()) == %{sent: 1, failed: 0}

    assert [
             {"POST", "/events/900/publish", %{"published" => false}},
             {"PATCH", "/events/900", _update},
             {"DELETE", "/attendance/701", nil}
           ] = writes()
  end

  test "an event deleted in D4H is made again", ctx do
    chore = chore_fixture(ctx.member, ctx.category, %{date: ~D[2026-10-06]})
    {:ok, chore} = SaveChore.accept_one(ctx.team, chore, ctx.user, DateTime.utc_now())
    event = Repo.get!(ChoreEvent, chore.chore_event_id)
    event |> Ecto.Changeset.change(d4h_activity_id: 900) |> Repo.update!()

    stub_d4h([], 404)
    assert SendChoreEvents.call(ctx.team, DateTime.utc_now()) == %{sent: 1, failed: 0}
    assert [{"POST", "/events", _create} | _rest] = writes()
  end

  test "moving an accepted chore to another category marks both events", ctx do
    chore = chore_fixture(ctx.member, ctx.category, %{date: ~D[2026-10-06]})
    {:ok, chore} = SaveChore.accept_one(ctx.team, chore, ctx.user, DateTime.utc_now())
    old = Repo.get!(ChoreEvent, chore.chore_event_id)
    ChoreEvent.record_send!(old, 900, nil, DateTime.utc_now())
    training = chore_category_fixture(ctx.team, %{title: "Training"})

    {:ok, moved} = SaveChore.change(ctx.team, chore, %{"chore_category_id" => training.id})

    assert moved.chore_event_id != old.id
    assert Repo.get!(ChoreEvent, old.id).needs_send
    assert Repo.get!(ChoreEvent, moved.chore_event_id).needs_send
  end
end
