defmodule App.Operation.RefreshD4HData.UpsertQualificationAwardsTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.MemberQualificationAward
  alias App.Operation.RefreshD4HData.UpsertQualificationAwards

  test "deletes this team's awards D4H no longer has" do
    team = team_fixture()
    qualification = qualification_fixture(team)
    member = member_fixture(team)
    kept = qualification_award_fixture(qualification, member)
    deleted = qualification_award_fixture(qualification, member)

    other_team = team_fixture()

    other =
      qualification_award_fixture(qualification_fixture(other_team), member_fixture(other_team))

    UpsertQualificationAwards.delete_stale(team.id, MapSet.new([kept.d4h_award_id]))

    assert Repo.get(MemberQualificationAward, kept.id)
    refute Repo.get(MemberQualificationAward, deleted.id)
    assert Repo.get(MemberQualificationAward, other.id)
  end
end
