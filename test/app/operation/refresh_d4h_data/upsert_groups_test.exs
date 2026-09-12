defmodule App.Operation.RefreshD4HData.UpsertGroupsTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Operation.RefreshD4HData.UpsertGroups

  test "deletes this team's groups D4H no longer has, with their memberships" do
    team = team_fixture()
    kept = group_fixture(team)
    deleted = group_fixture(team)
    membership = group_member_fixture(deleted, member_fixture(team))

    other = group_fixture(team_fixture())

    UpsertGroups.delete_stale(team.id, MapSet.new([kept.d4h_group_id]))

    assert Repo.get(Group, kept.id)
    refute Repo.get(Group, deleted.id)
    refute Repo.get(GroupMember, membership.id)
    assert Repo.get(Group, other.id)
  end
end
