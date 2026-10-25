defmodule App.Operation.SetGroupMembersTest do
  use ExUnit.Case, async: true

  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Operation.SetGroupMembers

  @robin %Member{id: 1, name: "Robin Tse"}
  @avery %Member{id: 2, name: "Avery Chen"}
  @quinn %Member{id: 3, name: "Quinn Laval"}
  @quinn_in %GroupMember{id: 30, member_id: 3, d4h_group_membership_id: 300}

  test "adding skips members in the group already, by name" do
    plan = SetGroupMembers.plan(:add, [@robin, @quinn, @avery], [@quinn_in])

    assert plan.changes == [
             %{member: @avery, group_member: nil},
             %{member: @robin, group_member: nil}
           ]

    assert plan.skipped == [@quinn]
  end

  test "removing skips members who aren't in the group, and keeps each membership" do
    plan = SetGroupMembers.plan(:remove, [@robin, @quinn], [@quinn_in])

    assert plan.changes == [%{member: @quinn, group_member: @quinn_in}]
    assert plan.skipped == [@robin]
  end

  test "nothing to do when every member is skipped" do
    assert %{changes: [], skipped: [@quinn]} = SetGroupMembers.plan(:add, [@quinn], [@quinn_in])
  end
end
