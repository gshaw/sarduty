defmodule App.Operation.DeleteTeamTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures
  import Swoosh.TestAssertions

  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.DeleteTeam
  alias App.Repo

  # A team with a row in most kinds of table, reached through team_id and through
  # parents that have none (attendances, group members, awards, letters, certificates).
  defp full_team(name) do
    team = team_fixture(%{name: name})
    member = member_fixture(team)
    activity = activity_fixture(team)
    attendance_fixture(activity, member)
    qualification = qualification_fixture(team)
    qualification_award_fixture(qualification, member)
    certificate_fixture(member, qualification)
    group = group_fixture(team)
    group_member_fixture(group, member)
    endorsement = endorsement_fixture(team)
    endorsement_qualification_fixture(endorsement, qualification)
    group_rule_fixture(group, endorsement)
    member_card_fixture(member)
    tax_credit_letter_fixture(member)
    item = equipment_item_fixture(team)
    equipment_usage_fixture(activity, item)
    template_fixture(team, "Truck 1", [item])
    chore_fixture(member, chore_category_fixture(team))
    away_period_fixture(member, ~D[2026-01-01], ~D[2026-01-31])
    team
  end

  setup do
    %{admin: make_admin(user_fixture()), team: full_team("Coast Range SAR")}
  end

  test "deletes every row the team has, and leaves other teams alone", %{
    admin: admin,
    team: team
  } do
    other = full_team("Valley SAR")
    other_counts = DeleteTeam.row_counts(other)
    assert map_size(DeleteTeam.row_counts(team)) > 15

    assert {:ok, nil} = DeleteTeam.call(team, "coast range sar ", admin)

    refute Repo.get(Team, team.id)
    assert DeleteTeam.row_counts(team) == %{}
    assert DeleteTeam.row_counts(other) == other_counts
    # The sandbox never commits, so check the keys the commit would.
    assert %{rows: []} = Repo.query!("PRAGMA foreign_key_check")
  end

  test "refuses a name that doesn't match", %{admin: admin, team: team} do
    assert {:error, :name_mismatch} = DeleteTeam.call(team, "Coast Range", admin)
    assert Repo.get(Team, team.id)
  end

  test "records the delete and emails the admins", %{admin: admin, team: team} do
    {:ok, _snapshot} = DeleteTeam.call(team, team.name, admin)

    assert %Event{user_id: user_id, data: %{"subdomain" => subdomain}} =
             Repo.get_by!(Event, kind: :team_deleted)

    assert user_id == admin.id
    assert subdomain == team.subdomain
    assert_email_sent(subject: "Team deleted from SAR Duty: Coast Range SAR")
  end

  test "name_matches? ignores case and spaces at either end", %{team: team} do
    assert DeleteTeam.name_matches?(team, "  COAST RANGE SAR")
    refute DeleteTeam.name_matches?(team, "Coast  Range SAR")
    refute DeleteTeam.name_matches?(team, nil)
  end

  # Every table that holds team rows is found, so a new one can't be missed.
  test "every table with a team_id is in the delete" do
    %{rows: rows} =
      Repo.query!(
        "SELECT m.name FROM sqlite_master m, pragma_table_info(m.name) c WHERE m.type = 'table' AND c.name = 'team_id'"
      )

    scoped = 1 |> DeleteTeam.scopes() |> Enum.map(&elem(&1, 0))

    for [table] <- rows, do: assert(table in scoped, "#{table} isn't deleted with its team")
    assert List.last(scoped) == "teams"
  end
end
