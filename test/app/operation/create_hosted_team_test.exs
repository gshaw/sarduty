defmodule App.Operation.CreateHostedTeamTest do
  # Not async: seeding a hosted team holds SQLite's write lock long enough to stall other tests.
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Group
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Team
  alias App.Operation.CreateHostedTeam

  defp params(overrides \\ %{}) do
    unique = System.unique_integer([:positive])

    Map.merge(
      %{
        "name" => "Colchester GSAR",
        "subdomain" => "colchester#{unique}",
        "timezone" => "America/Halifax",
        "manager_name" => "Robin Example",
        "manager_email" => "Robin#{unique}@example.com"
      },
      overrides
    )
  end

  test "the team's first manager can log in as soon as it's created" do
    params = params()
    assert {:ok, team} = CreateHostedTeam.call(params)

    assert D4H.hosted?(team)
    assert team.timezone == "America/Halifax"
    assert Team.refresh_state(team.d4h_refresh_result) == :ok
    assert Team.managed_by?(team, String.downcase(params["manager_email"]), DateTime.utc_now())
    assert [%Member{name: "Robin Example", d4h_permission: 0}] = Member.get_all(team.id)
  end

  test "sample data fills every list" do
    assert {:ok, team} = %{"sample_data" => "true"} |> params() |> CreateHostedTeam.call()
    member_ids = from(m in Member, where: m.team_id == ^team.id, select: m.id)

    assert team.id |> Member.get_all() |> length() == 11
    assert count(where(Activity, team_id: ^team.id)) == 8
    assert count(where(Group, team_id: ^team.id)) == 2
    assert count(where(Attendance, [a], a.member_id in subquery(member_ids))) > 40
    assert count(where(MemberQualificationAward, [a], a.member_id in subquery(member_ids))) > 10
  end

  defp count(query), do: Repo.aggregate(query, :count)

  test "a short name another team has is refused" do
    taken = team_fixture()

    assert {:error, changeset} =
             %{"subdomain" => taken.subdomain} |> params() |> CreateHostedTeam.call()

    assert "Another team uses this one. Choose another." in errors_on(changeset).subdomain
  end

  test "a short name must suit an address" do
    assert {:error, changeset} = %{"subdomain" => "9 bad"} |> params() |> CreateHostedTeam.call()
    assert errors_on(changeset).subdomain != []
  end
end
