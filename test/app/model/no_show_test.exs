defmodule App.Model.NoShowTest do
  use App.DataCase

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.Model.NoShow
  alias App.ViewData.TeamDashboardViewData

  @now ~U[2026-10-20 18:00:00Z]

  defp started(team, days_ago, title) do
    started_at = DateTime.add(@now, -days_ago, :day)
    activity_fixture(team, %{title: title, started_at: started_at, finished_at: started_at})
  end

  describe "to_follow_up/3 and Needs attention (#650)" do
    test "lists the last week's activities with no-shows nobody followed up, oldest first" do
      team = team_fixture()
      [a, b, c] = for _ <- 1..3, do: member_fixture(team)
      older = started(team, 6, "MIT training")
      newer = started(team, 1, "Rope practice")
      too_old = started(team, 8, "Swiftwater")
      done = started(team, 2, "Ground search")

      for member <- [a, b], do: NoShow.record!(older, member)
      NoShow.record!(newer, c)
      NoShow.record!(too_old, a)
      followed = NoShow.record!(done, a)

      user = AccountsFixtures.user_fixture()
      NoShow.set_followed_up(team, followed.id, {:note, nil}, user, DateTime.utc_now())

      other_team = team_fixture()
      other_team |> started(1, "Elsewhere") |> NoShow.record!(member_fixture(other_team))

      assert [%{title: "MIT training", count: 2}, %{title: "Rope practice", count: 1}] =
               NoShow.to_follow_up(team, DateTime.add(@now, -7, :day), @now)

      item =
        team |> TeamDashboardViewData.attention_items(@now) |> Enum.find(&(&1.key == :no_shows))

      assert item.title == "3 no-shows to follow up from 2 activities"
      assert item.activity_id == older.id
    end
  end

  test "for_member/3 lists the member's no-shows in the year, newest first" do
    team = team_fixture()
    member = member_fixture(team)
    last_year = activity_fixture(team, %{started_at: ~U[2025-06-01 18:00:00Z]})
    spring = activity_fixture(team, %{started_at: ~U[2026-04-01 18:00:00Z]})
    fall = activity_fixture(team, %{started_at: ~U[2026-09-01 18:00:00Z]})
    for activity <- [last_year, spring, fall], do: NoShow.record!(activity, member)
    NoShow.record!(spring, member_fixture(team))

    assert [%{activity: %{id: fall_id}}, %{activity: %{id: spring_id}}] =
             NoShow.for_member(member, 2026, team.timezone)

    assert {fall_id, spring_id} == {fall.id, spring.id}
  end
end
