defmodule App.Operation.SaveChoreTest do
  use ExUnit.Case, async: true

  alias App.Model.Chore
  alias App.Model.Member
  alias App.Operation.SaveChore

  # Another team admin should accept a team admin's chores (#697).
  describe "own_unmeant?/3" do
    setup do
      %{me: %Member{id: 1}, mine: %Chore{member_id: 1}, theirs: %Chore{member_id: 2}}
    end

    test "a team admin's own chore needs own: true", %{me: me, mine: mine, theirs: theirs} do
      assert SaveChore.own_unmeant?([theirs, mine], me, [])
      assert SaveChore.own_unmeant?([mine], me, own: false)
      refute SaveChore.own_unmeant?([theirs, mine], me, own: true)
    end

    test "someone else's chores don't", %{me: me, theirs: theirs} do
      refute SaveChore.own_unmeant?([theirs], me, [])
      refute SaveChore.own_unmeant?([], me, [])
    end

    test "a user who isn't one of the team's members has no chores of their own", ctx do
      refute SaveChore.own_unmeant?([ctx.mine, ctx.theirs], nil, [])
    end
  end

  describe "check_people/4" do
    setup do
      now = ~U[2026-11-25 12:00:00Z]

      %{
        now: now,
        context: %{retiring: MapSet.new([5]), now: now},
        me: %Member{id: 1, team_id: 9},
        riley: %Member{id: 2, team_id: 9}
      }
    end

    test "a team admin may log for others alone, a member only with themselves", ctx do
      %{me: me, riley: riley, context: context} = ctx
      assert SaveChore.check_people(me, [riley], :team_admin, context) == {:ok, [riley]}
      assert SaveChore.check_people(me, [riley], :member, context) == {:error, :without_you}
      assert SaveChore.check_people(me, [me, riley], :member, context) == {:ok, [me, riley]}
    end

    test "nobody listed is refused, and anyone listed twice counts once", ctx do
      %{me: me, riley: riley, context: context} = ctx
      assert SaveChore.check_people(me, [], :team_admin, context) == {:error, :nobody}

      assert SaveChore.check_people(me, [me, riley, riley], :member, context) ==
               {:ok, [me, riley]}
    end

    test "another team's member, a retiring one, a former one, or one not a person is refused",
         ctx do
      %{me: me, context: context, now: now} = ctx

      for other <- [
            %Member{id: 3, team_id: 8},
            %Member{id: 5, team_id: 9},
            %Member{id: 6, team_id: 9, left_at: DateTime.add(now, -1, :day)},
            %Member{id: 7, team_id: 9, d4h_status: "RETIRED"},
            %Member{id: 8, team_id: 9, not_a_person: true}
          ] do
        assert SaveChore.check_people(me, [me, other], :member, context) == {:error, :not_listed}
      end
    end

    test "a member who is not a person logs for themselves", %{context: context} do
      bot = %Member{id: 1, team_id: 9, not_a_person: true}
      assert SaveChore.check_people(bot, [bot], :member, context) == {:ok, [bot]}
    end
  end
end
