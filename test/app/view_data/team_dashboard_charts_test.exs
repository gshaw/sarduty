defmodule App.ViewData.TeamDashboardChartsTest do
  use ExUnit.Case, async: true

  alias App.ViewData.TeamDashboardCharts

  @team %{timezone: "America/Vancouver", lat: 49.7016, lng: -123.1558}
  @now ~U[2026-10-06 19:00:00Z]

  defp activity(id, kind, started_at, coordinate \\ "49.70,-123.15") do
    %{id: id, title: "Activity #{id}", kind: kind, started_at: started_at, coordinate: coordinate}
  end

  defp attend(started_at, minutes), do: %{started_at: started_at, minutes: minutes}

  # The charts for these rows, with the rest empty.
  defp shape(attrs) do
    %{now: @now, year: 2026, activities: [], attendance: [], members: []}
    |> Map.merge(attrs)
    |> TeamDashboardCharts.shape(@team)
  end

  test "this year is compared with the same days of last year" do
    charts =
      shape(%{
        activities: [
          activity(1, "incident", ~U[2026-09-01 18:00:00Z]),
          activity(2, "exercise", ~U[2026-02-01 18:00:00Z]),
          activity(3, "incident", ~U[2025-09-01 18:00:00Z]),
          # After Oct 6 last year, so not in last year's count to date.
          activity(4, "incident", ~U[2025-11-01 18:00:00Z])
        ],
        attendance: [
          attend(~U[2026-09-01 18:00:00Z], 120),
          attend(~U[2025-09-01 18:00:00Z], 60),
          attend(~U[2025-11-01 18:00:00Z], 600)
        ]
      })

    assert charts.activities_ytd == 2
    assert charts.incidents_ytd == 1
    assert charts.activities_last_ytd == 1
    assert charts.incidents_last_ytd == 1
    assert charts.minutes_ytd == 120
    assert charts.minutes_last_ytd == 60
  end

  test "the year starts on January 1 in the team's time zone" do
    # 23:30 on Dec 31 in Vancouver, which is already January 1 in UTC.
    charts =
      shape(%{activities: [activity(1, "exercise", ~U[2026-01-01 07:30:00Z])]})

    assert charts.activities_ytd == 0
  end

  test "members who joined this year are counted apart" do
    members = [
      %{id: 1, joined_at: ~U[2026-03-01 18:00:00Z]},
      %{id: 2, joined_at: ~U[2019-03-01 18:00:00Z]},
      %{id: 3, joined_at: nil}
    ]

    charts = shape(%{members: members})

    assert charts.members == 3
    assert charts.members_joined == 1
  end

  test "months run oldest to this month, stacked by kind" do
    charts =
      shape(%{
        activities: [
          activity(1, "incident", ~U[2026-10-02 18:00:00Z]),
          activity(2, "exercise", ~U[2026-10-03 18:00:00Z]),
          # More than a year ago, so in no month.
          activity(3, "incident", ~U[2025-09-30 18:00:00Z])
        ]
      })

    assert length(charts.activity_columns) == 12

    assert %{label: "Oct", values: %{incident: 1, exercise: 1}} =
             List.last(charts.activity_columns)

    assert List.last(charts.monthly_activities) == 2
    assert Enum.sum(charts.monthly_incidents) == 1
    assert length(charts.calendar_days) == 365
  end

  test "the map leaves off places far from the team's base and D4H's 0,0" do
    charts =
      shape(%{
        activities: [
          activity(1, "incident", ~U[2026-09-01 18:00:00Z]),
          activity(2, "incident", ~U[2026-09-02 18:00:00Z], "43.65,-79.38"),
          activity(3, "incident", ~U[2026-09-03 18:00:00Z], "0.00000,0.00000"),
          activity(4, "incident", ~U[2026-09-04 18:00:00Z], nil)
        ]
      })

    assert [%{kind: :incident, lat: 49.7, recent: false}] = charts.map_points
  end
end
