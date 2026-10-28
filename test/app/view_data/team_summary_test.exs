defmodule App.ViewData.TeamSummaryTest do
  use App.DataCase

  import App.DataFixtures

  alias App.ViewData.TeamSummary

  @now ~U[2026-10-04 12:00:00Z]

  # Once in the Retiring group, a member no longer counts as one (#514): not in an
  # organization's totals, and not a team admin who gets team admin email.
  test "retiring members count as neither members nor team admins" do
    team = team_fixture()
    leavers = group_fixture(team)
    team |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id) |> Repo.update!()

    manager_fixture(team, %{email: "staying@example.com"})
    group_member_fixture(leavers, manager_fixture(team, %{email: "retiring@example.com"}))
    group_member_fixture(leavers, member_fixture(team))

    assert TeamSummary.member_counts([team], @now) == %{team.id => 1}
    assert TeamSummary.team_admin_emails([team], @now) == %{team.id => ["staying@example.com"]}
  end
end
