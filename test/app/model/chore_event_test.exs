defmodule App.Model.ChoreEventTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Chore
  alias App.Model.ChoreEvent

  setup do
    team = team_fixture()
    member = member_fixture(team)
    %{team: team, member: member, category: chore_category_fixture(team)}
  end

  defp accepted(ctx, date, category \\ nil),
    do: chore_fixture(ctx.member, category || ctx.category, %{date: date, status: :accepted})

  defp event_id(chore), do: Repo.get!(Chore, chore.id).chore_event_id

  test "place! puts accepted chores on one event per chore category and month", ctx do
    training = chore_category_fixture(ctx.team, %{title: "Training"})
    one = accepted(ctx, ~D[2026-10-06])
    two = accepted(ctx, ~D[2026-10-31])
    november = accepted(ctx, ~D[2026-11-01])
    other = accepted(ctx, ~D[2026-10-06], training)
    waiting = chore_fixture(ctx.member, ctx.category, %{date: ~D[2026-10-06]})

    :ok = ChoreEvent.place!(ctx.team.id)

    assert event_id(one) == event_id(two)
    assert length(Enum.uniq([event_id(one), event_id(november), event_id(other)])) == 3
    assert event_id(waiting) == nil

    events = Repo.all(ChoreEvent)
    assert Enum.all?(events, & &1.needs_send)

    assert events |> Enum.map(& &1.month) |> Enum.uniq() |> Enum.sort(Date) == [
             ~D[2026-10-01],
             ~D[2026-11-01]
           ]
  end

  test "place! takes a chore that is no longer accepted off its event, and marks the event",
       ctx do
    chore = accepted(ctx, ~D[2026-10-06])
    :ok = ChoreEvent.place!(ctx.team.id)
    event = Repo.get!(ChoreEvent, event_id(chore))
    Repo.update_all(ChoreEvent, set: [needs_send: false])

    chore |> Ecto.Changeset.change(status: :declined) |> Repo.update!()
    :ok = ChoreEvent.place!(ctx.team.id)

    assert event_id(chore) == nil
    assert Repo.get!(ChoreEvent, event.id).needs_send
  end

  test "place! changes nothing when every chore is on its event", ctx do
    accepted(ctx, ~D[2026-10-06])
    :ok = ChoreEvent.place!(ctx.team.id)
    Repo.update_all(ChoreEvent, set: [needs_send: false])

    :ok = ChoreEvent.place!(ctx.team.id)

    assert [%{needs_send: false}] = Repo.all(ChoreEvent)
  end
end
