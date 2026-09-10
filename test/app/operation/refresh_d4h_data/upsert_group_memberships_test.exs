defmodule App.Operation.RefreshD4HData.UpsertGroupMembershipsTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.GroupMember
  alias App.Operation.RefreshD4HData.UpsertGroupMemberships

  test "deletes this team's memberships D4H no longer has" do
    team = team_fixture()
    group = group_fixture(team)
    kept = group_member_fixture(group, member_fixture(team))
    deleted = group_member_fixture(group, member_fixture(team))

    other_team = team_fixture()
    other = group_member_fixture(group_fixture(other_team), member_fixture(other_team))

    UpsertGroupMemberships.delete_stale(team.id, MapSet.new([kept.d4h_group_membership_id]))

    assert Repo.get(GroupMember, kept.id)
    refute Repo.get(GroupMember, deleted.id)
    assert Repo.get(GroupMember, other.id)
  end
end
