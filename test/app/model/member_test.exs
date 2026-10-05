defmodule App.Model.MemberTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Activity
  alias App.Model.Member

  test "takes whatever D4H holds, however long or odd" do
    # A D4H address field once held a paragraph of notes and broke a team's first refresh.
    member =
      member_fixture(team_fixture(), %{
        name: String.duplicate("n", 80),
        address: String.duplicate("a", 500),
        email: "not an email"
      })

    assert String.length(member.address) == 500
  end

  describe "include_primary_and_secondary_minutes/3" do
    setup do
      team = team_fixture(%{timezone: "America/Vancouver"})
      member = member_fixture(team)
      %{team: team, member: member}
    end

    test "8 pm on December 31 counts toward that year", %{team: team, member: member} do
      # 8:00 pm December 31, 2025 in Vancouver
      attend(team, member, ~U[2026-01-01 04:00:00Z], Activity.primary_hours_tag())

      assert primary_minutes(team, member, 2025) == 60
      assert primary_minutes(team, member, 2026) == 0
    end

    test "midnight on January 1 starts the year, with or without a stored Z",
         %{team: team, member: member} do
      attend(team, member, ~U[2026-01-01 08:00:00Z], Activity.primary_hours_tag())
      attendance = attend(team, member, ~U[2026-01-01 08:00:00Z], Activity.secondary_hours_tag())

      # Older rows were written without the Z.
      Repo.query!("UPDATE attendances SET started_at = '2026-01-01T08:00:00' WHERE id = ?", [
        attendance.id
      ])

      assert minutes(team, member, 2025) == {0, 0}
      assert minutes(team, member, 2026) == {60, 60}
    end
  end

  defp attend(team, member, started_at, tag) do
    activity = activity_fixture(team, %{started_at: started_at, tags: [tag]})
    attendance_fixture(activity, member, %{started_at: started_at})
  end

  defp primary_minutes(team, member, year), do: summary(team, member, year).primary_minutes

  defp minutes(team, member, year) do
    summary = summary(team, member, year)
    {summary.primary_minutes, summary.secondary_minutes}
  end

  defp summary(team, member, year) do
    Member
    |> where(id: ^member.id)
    |> Member.include_primary_and_secondary_minutes(team, year)
    |> Repo.one()
  end
end
