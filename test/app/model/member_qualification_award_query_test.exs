defmodule App.Model.MemberQualificationAwardQueryTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.MemberQualificationAward

  # The queries agree with active?/2: an award is good through its expiry day (#1058).
  test "an award counts through its expiry day on a Pacific team, and not the day after" do
    team = team_fixture()
    member = member_fixture(team)
    qualification = qualification_fixture(team)
    ends_at = Service.Convert.day_start(~D[2026-11-12], team.timezone)

    qualification_award_fixture(qualification, member, %{
      starts_at: Service.Convert.day_start(~D[2025-11-12], team.timezone),
      ends_at: ends_at
    })

    evening = DateTime.add(ends_at, 86_399)
    midnight = DateTime.add(ends_at, 1, :day)
    held = [{member.id, qualification.d4h_qualification_id}]

    assert MemberQualificationAward.get_all_active_for_team(team.id, evening) == held
    assert MemberQualificationAward.get_all_active_for_team(team.id, midnight) == []

    until = DateTime.add(evening, 60, :day)
    assert [%{member_id: id}] = MemberQualificationAward.expiring(team.id, evening, until)
    assert id == member.id
    assert MemberQualificationAward.expiring(team.id, midnight, until) == []
  end
end
