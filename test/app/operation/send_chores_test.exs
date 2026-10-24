defmodule App.Operation.SendChoresTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.ChangeSet
  alias App.Model.Chore
  alias App.Model.ChoreCategoryTag
  alias App.Model.ChoreEvent
  alias App.Operation.SaveChore
  alias App.Operation.SendChores

  @today ~D[2026-10-31]

  setup do
    %{user: user, team: team} =
      user_with_team_fixture(%{
        team: %{d4h_access_key: "team-key", member_logins: true, chores_enabled: true}
      })

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

  # D4H, sending each write to the test. `existing` is the attendance on any event.
  # `event_status` is 200, 404 for an event deleted in D4H, :approved, :no_publish for
  # a team whose events D4H will not publish, :no_tags when D4H refuses the tags, or
  # `{:tagged, id}` for an event that has the tag.
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

  defp answer(conn, "GET", "/events/900", _json, _existing, {:tagged, tag_id}),
    do:
      Req.Test.json(
        conn,
        Map.put(event(900, true), "tags", [%{"resourceType" => "Tag", "id" => tag_id}])
      )

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

  defp answer(conn, "POST", "/events/900/tags", _json, _existing, :no_tags),
    do: conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"title" => "Tag not found"})

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

  defp send_chores(ctx), do: SendChores.call(ctx.team, ctx.user, DateTime.utc_now())

  defp event_of(chore), do: Repo.get!(ChoreEvent, Repo.get!(Chore, chore.id).chore_event_id)

  test "accepting puts chores on their month's event; the send makes one event per category and month",
       ctx do
    one = accept(ctx, %{date: ~D[2026-09-06], minutes: 90})
    two = accept(ctx, %{date: ~D[2026-09-19], minutes: 30})
    october = accept(ctx, %{date: ~D[2026-10-04], minutes: 60})
    assert event_of(one).id == event_of(two).id
    assert event_of(october).id != event_of(one).id

    stub_d4h()
    assert send_chores(ctx) == %{events: 2, failed: 0}

    events = Repo.all(ChoreEvent)
    assert events |> Enum.map(& &1.month) |> Enum.sort(Date) == [~D[2026-09-01], ~D[2026-10-01]]
    assert Enum.all?(events, &(&1.d4h_activity_id == 900 and not &1.needs_send))

    creates = for {"POST", "/events", json} <- writes(), do: json
    titles = creates |> Enum.map(& &1["referenceDescription"]) |> Enum.sort()

    assert titles == [
             "Chores: Equipment maintenance, October 2026",
             "Chores: Equipment maintenance, September 2026"
           ]

    assert Enum.all?(creates, &(&1["fullTeam"] == false))

    [change_set | _rest] = Repo.all(ChangeSet)
    assert %{source: :chores, applied_by_user_id: user_id} = change_set
    assert user_id == ctx.user.id
  end

  test "a chore accepted after its month's event was sent goes on that event", ctx do
    first = accept(ctx, %{date: ~D[2026-10-06], minutes: 90})
    stub_d4h()
    send_chores(ctx)
    _sent = writes()

    second = accept(ctx, %{date: ~D[2026-10-19], minutes: 30})
    assert event_of(second).id == event_of(first).id
    assert [%{needs_send: true}] = Repo.all(ChoreEvent)

    stub_d4h([attendance(701, ctx.member, 90)])
    assert send_chores(ctx) == %{events: 1, failed: 0}

    writes = writes()
    refute Enum.any?(writes, &match?({"POST", "/events", _json}, &1))

    assert {"PATCH", "/events/900", %{"referenceDescription" => title}} =
             Enum.find(writes, &match?({"PATCH", "/events/900", _json}, &1))

    assert title == "Chores: Equipment maintenance, October 2026"

    assert {"PATCH", "/attendance/701", %{"endsAt" => "2026-10-01T09:00:00Z"}} =
             Enum.find(writes, &match?({"PATCH", "/attendance/701", _json}, &1))
  end

  test "the send tags the event and adds each member's total, then publishes", ctx do
    accept(ctx, %{date: ~D[2026-10-06], minutes: 90})

    stub_d4h()
    send_chores(ctx)

    [create, tags, add, publish] = writes()
    assert {"POST", "/events", %{"startsAt" => "2026-10-01T07:00:00Z"}} = create
    assert {"POST", "/events/900/tags", %{"tagIds" => tag_ids}} = tags
    assert Enum.sort(tag_ids) == ctx.tags |> Enum.map(& &1.d4h_tag_id) |> Enum.sort()

    assert {"POST", "/attendance", %{"activityId" => 900, "endsAt" => "2026-10-01T08:30:00Z"}} =
             add

    assert {"POST", "/events/900/publish", %{"published" => true}} = publish
  end

  test "declining a sent chore takes it off its event, and the send takes the member off",
       ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()
    send_chores(ctx)
    _sent = writes()
    chore = Repo.get!(Chore, chore.id)

    {:ok, chore} =
      SaveChore.decline(ctx.team, chore, "Not a chore.", ctx.user, DateTime.utc_now())

    assert chore.chore_event_id == nil
    [event] = Repo.all(ChoreEvent)
    assert event.needs_send

    stub_d4h([attendance(701, ctx.member, 60)])
    assert send_chores(ctx) == %{events: 1, failed: 0}

    assert [
             {"POST", "/events/900/publish", %{"published" => false}},
             {"PATCH", "/events/900", _update},
             {"DELETE", "/attendance/701", nil}
           ] = writes()

    refute Repo.get!(ChoreEvent, event.id).needs_send
  end

  test "a sent chore changed within its month stays on its event; moved to another month, it goes to that month's",
       ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()
    send_chores(ctx)
    october = event_of(chore)

    {:ok, longer} =
      SaveChore.change(ctx.team, Repo.get!(Chore, chore.id), %{"minutes" => "120"}, @today)

    assert longer.chore_event_id == october.id
    assert Repo.get!(ChoreEvent, october.id).needs_send

    {:ok, moved} = SaveChore.change(ctx.team, longer, %{"date" => "2026-09-28"}, @today)
    september = Repo.get!(ChoreEvent, moved.chore_event_id)
    assert %{month: ~D[2026-09-01], needs_send: true} = september
    assert Repo.get!(ChoreEvent, october.id).needs_send
  end

  test "two events for one month, as the move to monthly events left them, become one", ctx do
    month = ~D[2026-10-01]
    older = insert_sent_event(ctx, month, 900)
    newer = insert_sent_event(ctx, month, 901)
    one = accepted_on(ctx, older, ~D[2026-10-21])
    two = accepted_on(ctx, newer, ~D[2026-10-22])

    stub_d4h()
    assert send_chores(ctx) == %{events: 2, failed: 0}

    assert event_of(one).id == older.id
    assert event_of(two).id == older.id
    assert Enum.any?(writes(), &match?({"PATCH", "/events/901", %{"description" => _}}, &1))
    assert [%{event: %{id: id}}] = ChoreEvent.get_all_with_totals(ctx.team.id)
    assert id == older.id
  end

  test "an event whose chores were declined before it was sent is dropped", ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    assert [_event] = Repo.all(ChoreEvent)

    {:ok, _chore} =
      SaveChore.decline(ctx.team, chore, "Not a chore.", ctx.user, DateTime.utc_now())

    stub_d4h()
    assert send_chores(ctx) == %{events: 1, failed: 0}
    assert writes() == []
    assert Repo.all(ChoreEvent) == []
  end

  test "an event deleted in D4H is made again", ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()
    send_chores(ctx)
    _sent = writes()

    {:ok, _chore} =
      SaveChore.change(ctx.team, Repo.get!(Chore, chore.id), %{"minutes" => "45"}, @today)

    stub_d4h([], 404)
    assert send_chores(ctx) == %{events: 1, failed: 0}
    assert [{"POST", "/events", _create} | _rest] = writes()
  end

  test "an event D4H will not publish stays a draft and counts as sent, with a note", ctx do
    accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h([], :no_publish)

    assert send_chores(ctx) == %{events: 1, failed: 0}

    [event] = Repo.all(ChoreEvent)

    assert %{
             d4h_activity_id: 900,
             needs_send: false,
             send_note: "Left as a draft: D4H would not publish it."
           } = event
  end

  test "an event D4H calls approved is sent like any other: approved only mirrors published",
       ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()
    send_chores(ctx)
    _sent = writes()

    {:ok, _chore} =
      SaveChore.change(ctx.team, Repo.get!(Chore, chore.id), %{"minutes" => "45"}, @today)

    stub_d4h([attendance(701, ctx.member, 60)], :approved)
    assert send_chores(ctx) == %{events: 1, failed: 0}

    assert Enum.any?(writes(), &match?({"PATCH", "/attendance/701", _json}, &1))
    assert %{needs_send: false, send_note: nil} = event_of(chore)
  end

  test "a chore sent after the page loaded it still marks its event when declined", ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()
    send_chores(ctx)
    [event] = Repo.all(ChoreEvent)
    refute event.needs_send

    {:ok, _chore} =
      SaveChore.decline(ctx.team, chore, "Not a chore", ctx.user, DateTime.utc_now())

    assert Repo.get!(ChoreEvent, event.id).needs_send
    assert Repo.get!(Chore, chore.id).chore_event_id == nil
  end

  test "a new event D4H will not tag waits to be sent again, and that send tags it", ctx do
    accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h([], :no_tags)

    assert send_chores(ctx) == %{events: 1, failed: 1}
    [event] = Repo.all(ChoreEvent)
    assert %{d4h_activity_id: 900, needs_send: true} = event
    assert event.send_note =~ "Sent without its tags. Send the changes to try again."
    _sent = writes()

    stub_d4h()
    assert send_chores(ctx) == %{events: 1, failed: 0}
    assert Enum.any?(writes(), &match?({"POST", "/events/900/tags", _json}, &1))
    assert %{needs_send: false, send_note: nil} = Repo.get!(ChoreEvent, event.id)
  end

  test "a sent event that has its hours tag is not tagged again", ctx do
    chore = accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()
    send_chores(ctx)
    _sent = writes()

    {:ok, _chore} =
      SaveChore.change(ctx.team, Repo.get!(Chore, chore.id), %{"minutes" => "45"}, @today)

    stub_d4h([], {:tagged, hd(ctx.tags).d4h_tag_id})
    assert send_chores(ctx) == %{events: 1, failed: 0}
    refute Enum.any?(writes(), &match?({_method, "/events/900/tags", _json}, &1))
  end

  test "a send cut short leaves its event with changes to send", ctx do
    accept(ctx, %{date: ~D[2026-10-06]})
    Req.Test.stub(App.Adapter.D4H, fn _conn -> raise "connection lost" end)

    assert_raise RuntimeError, fn -> send_chores(ctx) end
    assert [%{needs_send: true, d4h_activity_id: nil}] = Repo.all(ChoreEvent)
  end

  test "without the team's hours tag in D4H, no event is made", ctx do
    ctx.tags |> hd() |> Repo.delete!()
    accept(ctx, %{date: ~D[2026-10-06]})
    stub_d4h()

    assert send_chores(ctx) == %{events: 1, failed: 1}
    assert writes() == []
    [event] = Repo.all(ChoreEvent)
    assert %{d4h_activity_id: nil, needs_send: true} = event
    assert event.send_note == "D4H has no tag named Primary Hours, this category's hours tag."
  end

  defp insert_sent_event(ctx, month, d4h_activity_id) do
    Repo.insert!(%ChoreEvent{
      team_id: ctx.team.id,
      chore_category_id: ctx.category.id,
      month: month,
      d4h_activity_id: d4h_activity_id,
      needs_send: true
    })
  end

  defp accepted_on(ctx, event, date),
    do:
      chore_fixture(ctx.member, ctx.category, %{
        date: date,
        status: :accepted,
        chore_event_id: event.id
      })
end
