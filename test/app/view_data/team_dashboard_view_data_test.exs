defmodule App.ViewData.TeamDashboardViewDataTest do
  use ExUnit.Case, async: true

  alias App.ViewData.TeamDashboardViewData

  @now ~U[2026-10-06 16:00:00Z]

  defp activity(id, starts_in_hours, hours_long \\ 2) do
    started_at = DateTime.add(@now, round(starts_in_hours * 60), :minute)
    %{id: id, started_at: started_at, finished_at: DateTime.add(started_at, hours_long, :hour)}
  end

  defp ids(activities), do: Enum.map(activities, & &1.id)

  test "NextUp is an activity starting within 12 hours, and Coming up leaves it out" do
    {next_up, coming_up} =
      TeamDashboardViewData.agenda([activity(2, 30), activity(1, 3)], @now)

    assert next_up.id == 1
    assert ids(coming_up) == [2]
  end

  test "an activity still running is NextUp until it finishes" do
    {next_up, _} = TeamDashboardViewData.agenda([activity(1, -2, 4)], @now)
    assert next_up.id == 1

    {next_up, coming_up} = TeamDashboardViewData.agenda([activity(1, -3, 2)], @now)
    assert next_up == nil
    assert coming_up == []
  end

  test "nothing within 12 hours means no NextUp" do
    {next_up, coming_up} = TeamDashboardViewData.agenda([activity(1, 12.5)], @now)

    assert next_up == nil
    assert ids(coming_up) == [1]
  end

  test "Coming up is the next 5 within 14 days" do
    activities = for day <- 1..15, do: activity(day, day * 24)

    {nil, coming_up} = TeamDashboardViewData.agenda(activities, @now)

    assert ids(coming_up) == [1, 2, 3, 4, 5]

    {nil, coming_up} = TeamDashboardViewData.agenda([activity(15, 15 * 24)], @now)
    assert coming_up == []
  end
end
