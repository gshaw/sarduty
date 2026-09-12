defmodule App.Operation.RefreshD4HData.UpsertQualificationsTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Operation.RefreshD4HData.UpsertQualifications

  test "deletes this team's qualifications D4H no longer has, with their awards" do
    team = team_fixture()
    kept = qualification_fixture(team)
    deleted = qualification_fixture(team)
    award = qualification_award_fixture(deleted, member_fixture(team))

    other_team = team_fixture()
    other = qualification_fixture(other_team)

    UpsertQualifications.delete_stale(team.id, MapSet.new([kept.d4h_qualification_id]))

    assert Repo.get(Qualification, kept.id)
    refute Repo.get(Qualification, deleted.id)
    refute Repo.get(MemberQualificationAward, award.id)
    assert Repo.get(Qualification, other.id)
  end
end
