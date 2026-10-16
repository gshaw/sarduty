defmodule App.Model.GroupRuleTest do
  use ExUnit.Case, async: true

  alias App.Model.GroupRule

  # 30 is in 20, which is in 10's rules; 40 has a Not in rule naming 10.
  @rules %{
    30 => [%{targets: [{:group, 20}, {:endorsement, 1}]}],
    20 => [%{targets: [{:group, 10}]}],
    40 => [%{targets: [{:group, 10}]}]
  }

  test "a group may name another unless that leads back to it" do
    refute GroupRule.can_name?(@rules, 10, 10)
    refute GroupRule.can_name?(@rules, 10, 30)
    assert GroupRule.can_name?(@rules, 30, 40)
    assert GroupRule.can_name?(@rules, 10, 50)
  end

  test "a loop already in the data stops" do
    assert GroupRule.can_name?(
             %{1 => [%{targets: [{:group, 2}]}], 2 => [%{targets: [{:group, 1}]}]},
             3,
             1
           )
  end

  test "lists the groups whose rules name a group" do
    assert @rules |> GroupRule.used_by(10) |> Enum.sort() == [20, 40]
    assert GroupRule.used_by(@rules, 30) == []
  end
end
