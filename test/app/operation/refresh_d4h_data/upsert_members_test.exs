defmodule App.Operation.RefreshD4HData.UpsertMembersTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.UpsertMembers

  # 11 pm on Sep 30 in Vancouver.
  @now ~U[2026-10-01 06:00:00Z]

  test "marks this team's members D4H no longer lists as retired, as of today" do
    team = team_fixture()
    listed = member_fixture(team)
    missing = member_fixture(team)
    retired = member_fixture(team, %{left_at: ~U[2025-01-01 08:00:00Z]})
    other = member_fixture(team_fixture())

    UpsertMembers.mark_retired(team, MapSet.new([listed.d4h_member_id]), @now)

    assert Repo.get(Member, listed.id).left_at == nil
    # The start of Sep 30 on the team's clock.
    assert Repo.get(Member, missing.id).left_at == ~U[2026-09-30 07:00:00Z]
    assert Repo.get(Member, retired.id).left_at == ~U[2025-01-01 08:00:00Z]
    assert Repo.get(Member, other.id).left_at == nil
  end

  # D4H keeps both as the day at 00:00 UTC, the evening before in Vancouver (#1058).
  test "a join and leave date are kept as the start of D4H's day on a Pacific team's clock" do
    team = team_fixture(%{d4h_access_key: "team-key"})

    Req.Test.stub(D4H, fn conn ->
      Req.Test.json(conn, %{
        "results" => [
          %{
            "id" => 4242,
            "name" => "Sam Rivera",
            "owner" => %{"resourceType" => "Team", "id" => team.d4h_team_id},
            "email" => %{"value" => "sam@example.com"},
            "mobile" => %{"phone" => nil},
            "startsAt" => "2018-01-01T00:00:00.000Z",
            "endsAt" => "2026-07-15T00:00:00.000Z",
            "status" => "RETIRED"
          }
        ],
        "page" => 0,
        "pageSize" => 1,
        "totalSize" => 1
      })
    end)

    team |> D4H.build_context_from_team() |> UpsertMembers.call(team, Progress.quiet(team.id))

    member = Repo.get_by!(Member, team_id: team.id, d4h_member_id: 4242)
    assert member.joined_at == ~U[2018-01-01 08:00:00Z]
    assert member.left_at == ~U[2026-07-15 07:00:00Z]
    assert Service.Format.date_short(member.joined_at, team.timezone) =~ "Jan 1, 2018"
    assert Service.YearRange.year_in(member.joined_at, team.timezone) == 2018
  end
end
