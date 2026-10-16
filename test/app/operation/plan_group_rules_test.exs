defmodule App.Operation.PlanGroupRulesTest do
  use ExUnit.Case, async: true

  alias App.Operation.PlanGroupRules

  # Groups by D4H id: 1 GSAR with an endorsement, 2 Swiftwater starts from GSAR, 3 starts
  # from Swiftwater and has nothing of its own, 4 starts from a group with no rule, 5
  # starts from a group D4H dropped.
  @group_endorsements [{1, 100}, {2, 200}, {1, 101}]
  @parents %{2 => 1, 3 => 2, 4 => 6, 5 => 9}
  @groups [1, 2, 3, 4, 5, 6]

  test "parents come first, then each endorsement as its own In rule" do
    assert PlanGroupRules.plan(@group_endorsements, @parents, @groups).rules == [
             {2, {:group, 1}},
             {3, {:group, 2}},
             {1, {:endorsement, 100}},
             {2, {:endorsement, 200}},
             {1, {:endorsement, 101}}
           ]
  end

  test "a parent that adds nothing today is dropped, with why" do
    assert PlanGroupRules.plan(@group_endorsements, @parents, @groups).dropped == [
             %{d4h_group_id: 4, parent: 6, why: :no_rules},
             %{d4h_group_id: 5, parent: 9, why: :not_in_d4h}
           ]
  end

  test "a parent whose own parent D4H dropped has only its own rule" do
    plan = PlanGroupRules.plan([], %{2 => 1, 1 => 9}, [1, 2])

    assert plan.rules == []
    assert Enum.map(plan.dropped, & &1.why) == [:not_in_d4h, :no_rules]
  end

  test "a loop is dropped" do
    plan = PlanGroupRules.plan([{1, 100}], %{1 => 2, 2 => 1}, [1, 2])

    assert plan.rules == [{1, {:endorsement, 100}}]
    assert Enum.map(plan.dropped, & &1.why) == [:loop, :loop]
  end
end
