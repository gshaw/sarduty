defmodule App.Operation.RefreshD4HData.UpsertMembersTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Member
  alias App.Operation.RefreshD4HData.UpsertMembers

  @now ~U[2026-10-01 06:00:00Z]

  test "marks this team's members D4H no longer lists as departed" do
    team = team_fixture()
    listed = member_fixture(team)
    missing = member_fixture(team)
    retired = member_fixture(team, %{left_at: ~U[2025-01-01 00:00:00Z]})
    other = member_fixture(team_fixture())

    UpsertMembers.mark_departed(team.id, MapSet.new([listed.d4h_member_id]), @now)

    assert Repo.get(Member, listed.id).left_at == nil
    assert Repo.get(Member, missing.id).left_at == @now
    assert Repo.get(Member, retired.id).left_at == ~U[2025-01-01 00:00:00Z]
    assert Repo.get(Member, other.id).left_at == nil
  end
end
