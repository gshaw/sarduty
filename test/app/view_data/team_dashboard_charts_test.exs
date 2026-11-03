defmodule App.ViewData.TeamDashboardChartsTest do
  # The map's rules, shared by a report's chart map, the Dashboard, and the year page.
  use ExUnit.Case, async: true

  alias App.ViewData.TeamDashboardCharts

  @team %{timezone: "America/Vancouver", lat: 49.7016, lng: -123.1558}
  @now ~U[2026-10-06 19:00:00Z]

  defp activity(id, started_at, coordinate \\ "49.70,-123.15") do
    %{title: "Activity #{id}", kind: :incident, started_at: started_at, coordinate: coordinate}
  end

  test "the map leaves off places far from the team's base and D4H's 0,0" do
    points =
      TeamDashboardCharts.map_points(
        [
          activity(1, ~U[2026-08-01 18:00:00Z]),
          activity(2, ~U[2026-09-02 18:00:00Z], "43.65,-79.38"),
          activity(3, ~U[2026-09-03 18:00:00Z], "0.00000,0.00000"),
          activity(4, ~U[2026-09-04 18:00:00Z], nil)
        ],
        @team,
        @now
      )

    assert [%{kind: :incident, lat: 49.7, recent: false}] = points
  end

  # LAST_N_DAYS:30, the app's one "last 30 days": today and the 30 whole days before it.
  test "large dots are the last 30 days, whole days in the team's time zone" do
    points =
      TeamDashboardCharts.map_points(
        [
          activity(1, ~U[2026-09-06 08:00:00Z]),
          activity(2, ~U[2026-09-06 06:00:00Z])
        ],
        @team,
        @now
      )

    assert Enum.map(points, & &1.recent) == [true, false]
  end
end
