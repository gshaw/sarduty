defmodule App.Operation.SendChoresTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.ChangeSet
  alias App.Model.Chore
  alias App.Model.ChoreCategoryTag
  alias App.Model.ChoreEvent
  alias App.Operation.SaveChore
  alias App.Operation.SendChores

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

  # D4H, sending each write to the test. `existing` is the attendance on event 900.
  # `event_status` is 200, 404 for an event deleted in D4H, :approved, or :no_publish for
  # a team whose events D4H will not publish.
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

  defp answer(conn, "GET", "/events/900", _json, _existing, :approved),
    do: Req.Test.json(conn, Map.put(event(900, true), "approved", true))

  defp answer(
         conn,
         "POST",
         "/events/900/publish",
         %{"published" => true},
         _existing,
         :no_publish
       ),
       do:
         conn
         |> Plug.Conn.put_status(409)
         |> Req.Test.json(%{
           "title" => "Activity cannot be marked ready for approval or published"
         })

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

  defp accept(ctx, attrs) do
    chore = chore_fixture(ctx.member, ctx.category, attrs)
    {:ok, chore} = SaveChore.accept_one(ctx.team, chore, ctx.user, DateTime.utc_now())
    chore
  end

  defp send_chores(ctx, chores),
    do: SendChores.call(ctx.team, Enum.map(chores, & &1.id), ctx.user, DateTime.utc_now())

  test "accepting waits; the send makes one event per category and year", ctx do
    one = accept(ctx, %{date: ~D[2026-10-06], minutes: 90})
    two = accept(ctx, %{date: ~D[2026-10-19], minutes: 30})
    january = accept(ctx, %{date: ~D[2027-01-04], minutes: 60})
    assert Repo.all(ChoreEvent) == []

    stub_d4h()
    assert send_chores(ctx, [one, two, january]) == %{chores: 3, events: 2, failed: 0}

    events = Repo.all(ChoreEvent)
    assert events |> Enum.map(& &1.year) |> Enum.sort() == [2026, 2027]
    assert Enum.all?(events, &(&1.d4h_activity_id == 900 and not &1.needs_send))

    creates = for {"POST", "/events", json} <- writes(), do: json
    titles = creates |> Enum.map(& &1["referenceDescription"]) |> Enum.sort()

    assert titles == [
             "Chores: Equipment maintenance, Jan 4, 2027",
             "Chores: Equipment maintenance, Oct 6 to Oct 19, 2026"
           ]

    assert Enum.all?(creates, &(&1["fullTeam"] == false))

    [change_set | _rest] = Repo.all(ChangeSet)
    assert %{source: :chores, applied_by_user_id: user_id} = change_set
    assert user_id == ctx.user.id
  end

  test "the send tags the event and adds each member's total, then publishes", ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06], minutes: 90})

    stub_d4h()
    send_chores(ctx, [chore])

    [create, tags, add, publish] = writes()
    assert {"POST", "/events", %{"startsAt" => "2026-10-06T07:00:00Z"}} = create
    assert {"POST", "/events/900/tags", %{"tagIds" => tag_ids}} = tags
    assert Enum.sort(tag_ids) == ctx.tags |> Enum.map(& &1.d4h_tag_id) |> Enum.sort()

    assert {"POST", "/attendance", %{"activityId" => 900, "endsAt" => "2026-10-06T08:30:00Z"}} =
             add

    assert {"POST", "/events/900/publish", %{"published" => true}} = publish
  end

  test "declining a sent chore marks its event; sending the changes takes the member off",
       ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()
    send_chores(ctx, [chore])
    _sent = writes()
    chore = Repo.get!(Chore, chore.id)

    {:ok, chore} =
      SaveChore.decline(ctx.team, chore, "Not a chore.", ctx.user, DateTime.utc_now())

    assert chore.chore_event_id == nil
    [event] = Repo.all(ChoreEvent)
    assert event.needs_send

    stub_d4h([attendance(701, ctx.member, 60)])
    assert SendChores.send_changes(ctx.team, event, ctx.user, DateTime.utc_now()) == :sent

    assert [
             {"POST", "/events/900/publish", %{"published" => false}},
             {"PATCH", "/events/900", _update},
             {"DELETE", "/attendance/701", nil}
           ] = writes()

    refute Repo.get!(ChoreEvent, event.id).needs_send
  end

  test "a sent chore changed within its event stays on it; moved to another category, it is ready to send again",
       ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()
    send_chores(ctx, [chore])
    chore = Repo.get!(Chore, chore.id)
    event_id = chore.chore_event_id

    {:ok, longer} = SaveChore.change(ctx.team, chore, %{"minutes" => "120"})
    assert longer.chore_event_id == event_id
    assert Repo.get!(ChoreEvent, event_id).needs_send

    training = chore_category_fixture(ctx.team, %{title: "Training"})
    {:ok, moved} = SaveChore.change(ctx.team, longer, %{"chore_category_id" => training.id})
    assert moved.chore_event_id == nil
    assert [%{id: id}] = Chore.get_ready(ctx.team.id)
    assert id == chore.id
  end

  test "an event deleted in D4H is made again", ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()
    send_chores(ctx, [chore])
    _sent = writes()
    [event] = Repo.all(ChoreEvent)
    {:ok, _chore} = SaveChore.change(ctx.team, Repo.get!(Chore, chore.id), %{"minutes" => "45"})

    stub_d4h([], 404)
    assert SendChores.send_changes(ctx.team, event, ctx.user, DateTime.utc_now()) == :sent
    assert [{"POST", "/events", _create} | _rest] = writes()
  end

  test "an event D4H will not publish stays a draft and counts as sent, with a note", ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h([], :no_publish)

    assert send_chores(ctx, [chore]) == %{chores: 1, events: 1, failed: 0}

    [event] = Repo.all(ChoreEvent)

    assert %{
             d4h_activity_id: 900,
             needs_send: false,
             send_note: "Left as a draft: D4H would not publish it."
           } = event
  end

  test "an event D4H has approved is locked: nothing is written, and changes no longer wait",
       ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()
    send_chores(ctx, [chore])
    _sent = writes()
    {:ok, _chore} = SaveChore.change(ctx.team, Repo.get!(Chore, chore.id), %{"minutes" => "45"})
    [event] = Repo.all(ChoreEvent)

    stub_d4h([], :approved)
    assert SendChores.send_changes(ctx.team, event, ctx.user, DateTime.utc_now()) == :locked
    assert writes() == []

    event = Repo.get!(ChoreEvent, event.id)
    assert %{locked: true, needs_send: false} = event
    assert event.send_note =~ "Approved in D4H"

    {:ok, _chore} = SaveChore.change(ctx.team, Repo.get!(Chore, chore.id), %{"minutes" => "50"})
    refute Repo.get!(ChoreEvent, event.id).needs_send
  end
end
