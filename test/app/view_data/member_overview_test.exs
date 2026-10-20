defmodule App.ViewData.MemberOverviewTest do
  use ExUnit.Case, async: true

  alias App.ViewData.MemberOverview

  @now ~U[2026-10-20 19:00:00Z]
  @tz "America/Vancouver"

  defp row(started_at, kind, minutes) do
    %{
      started_at: started_at,
      finished_at: DateTime.add(started_at, minutes * 60),
      duration_in_minutes: nil,
      activity: %{activity_kind: kind}
    }
  end

  defp award(title, ends_at), do: %{qualification: %{title: title}, ends_at: ends_at}

  test "counts this year in the team's time zone, and keeps the last 12 months for the map" do
    rows = [
      row(~U[2026-10-15 18:00:00Z], "incident", 570),
      row(~U[2026-10-11 18:00:00Z], "exercise", 240),
      # 23:00 on Dec 31, 2025 in Vancouver: last year.
      row(~U[2026-01-01 07:00:00Z], "incident", 60),
      row(~U[2025-06-01 18:00:00Z], "event", 60)
    ]

    overview = MemberOverview.build(rows, [], @now, @tz)

    assert overview.year == 2026
    assert overview.minutes == 810
    assert overview.activities == 2
    assert overview.incidents == 1
    assert length(overview.last_12_months) == 3
    assert length(overview.lately) == 3
  end

  test "hours by kind count every activity, in a fixed order, leaving out kinds with none" do
    rows = [
      row(~U[2026-10-15 18:00:00Z], "exercise", 240),
      row(~U[2026-10-11 18:00:00Z], "incident", 60),
      row(~U[2026-09-11 18:00:00Z], "exercise", 30)
    ]

    assert MemberOverview.hours_by_kind(rows) == [
             %{kind: "incident", label: "Incidents", minutes: 60},
             %{kind: "exercise", label: "Exercises", minutes: 270}
           ]

    assert MemberOverview.hours_by_kind([]) == []
  end

  test "qualifications count what the member holds now, and the next one to expire" do
    groups = [
      within_180_days: [%{award: award("Swiftwater", ~U[2027-03-01 00:00:00Z])}],
      within_60_days: [%{award: award("First Aid", ~U[2026-11-30 00:00:00Z])}],
      never: [%{award: award("GSAR", nil)}],
      expired: [%{award: award("Rope", ~U[2024-09-30 00:00:00Z])}]
    ]

    %{qualifications: qualifications} = MemberOverview.build([], groups, @now, @tz)
    assert qualifications.count == 3
    assert qualifications.next.qualification.title == "First Aid"

    assert %{qualifications: %{count: 1, next: nil}} =
             MemberOverview.build([], [never: [%{award: award("GSAR", nil)}]], @now, @tz)
  end
end
