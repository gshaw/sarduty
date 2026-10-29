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
end
