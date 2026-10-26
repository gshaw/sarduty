defmodule App.ViewData.MemberYearTest do
  use ExUnit.Case, async: true

  alias App.ViewData.MemberYear

  @tz "America/Toronto"
  @tags %{primary: "Primary Hours", secondary: "Secondary Hours", other: nil}
  @now ~U[2026-06-15 18:00:00Z]

  # An attended row of `hours` from `started_at`, for an activity of its own.
  defp row(started_at, hours, opts \\ []) do
    id = System.unique_integer([:positive])

    %{
      member_id: 1,
      activity_id: Keyword.get(opts, :activity_id, id),
      started_at: started_at,
      finished_at: DateTime.add(started_at, hours * 3600),
      duration_in_minutes: hours * 60,
      activity: %{
        tags: Keyword.get(opts, :tags, ["Primary Hours"]),
        activity_kind: Keyword.get(opts, :kind, "exercise"),
        chore_minutes: Keyword.get(opts, :chore_minutes)
      }
    }
  end

  describe "hours/4" do
    test "adds up rows on chore activities, as the letter does (#584)" do
      # Both start at 00:00 on March 1 in Toronto, as every chore row does.
      rows = [
        row(~U[2026-03-01 05:00:00Z], 5, chore_minutes: 300),
        row(~U[2026-03-01 05:00:00Z], 2, chore_minutes: 120)
      ]

      assert MemberYear.hours(rows, 2026, @tz, @tags).primary_minutes == 420
    end

    test "counts as the letter does: tagged rows that started in the year" do
      rows = [
        row(~U[2026-03-02 23:00:00Z], 3),
        row(~U[2026-03-09 23:00:00Z], 2, tags: ["Secondary Hours"]),
        row(~U[2026-03-16 23:00:00Z], 4, tags: []),
        # Dec 31 in Toronto, so last year's.
        row(~U[2026-01-01 03:00:00Z], 5)
      ]

      assert MemberYear.hours(rows, 2026, @tz, @tags) ==
               %{primary_minutes: 180, secondary_minutes: 120, total_minutes: 300}
    end

    test "no rows, no hours" do
      assert MemberYear.hours([], 2026, @tz, @tags).total_minutes == 0
    end
  end

  test "activities and incidents count each activity once" do
    rows = [
      row(~U[2026-05-01 14:00:00Z], 2, activity_id: 7, kind: "incident"),
      row(~U[2026-05-01 18:00:00Z], 1, activity_id: 7, kind: "incident"),
      row(~U[2026-05-03 14:00:00Z], 2, kind: "event")
    ]

    assert MemberYear.activities(rows) == 2
    assert MemberYear.incidents(rows) == 1
  end

  describe "summary/6" do
    test "this year against the same days of last year" do
      rows = [
        row(~U[2026-02-10 23:00:00Z], 4),
        row(~U[2026-05-20 23:00:00Z], 2, kind: "incident")
      ]

      before = [
        row(~U[2025-03-10 23:00:00Z], 3),
        # After June 15 last year, so not yet this time last year.
        row(~U[2025-09-10 23:00:00Z], 8, kind: "incident")
      ]

      summary = MemberYear.summary(rows, before, 2026, @now, @tz, @tags)

      assert summary.total_minutes == 360
      assert summary.activities == 2
      assert summary.incidents == 1
      assert summary.versus.hours == {6, 3}
      assert summary.versus.activities == {2, 1}
      assert summary.versus.incidents == {1, 0}
    end

    test "a past year against the whole year before it" do
      rows = [row(~U[2025-04-10 23:00:00Z], 4)]
      before = [row(~U[2024-03-10 23:00:00Z], 3), row(~U[2024-11-10 23:00:00Z], 8)]

      summary = MemberYear.summary(rows, before, 2025, @now, @tz, @tags)

      assert summary.versus.hours == {4, 11}
      assert summary.versus.activities == {1, 2}
      assert length(summary.monthly.activities) == 12
    end

    test "a month a value up to this month, for the sparklines" do
      rows = [
        row(~U[2026-01-10 23:00:00Z], 2),
        row(~U[2026-03-10 23:00:00Z], 3, kind: "incident"),
        row(~U[2026-03-17 23:00:00Z], 1, tags: [])
      ]

      summary = MemberYear.summary(rows, [], 2026, @now, @tz, @tags)

      assert summary.monthly.hours == [2, 0, 3, 0, 0, 0]
      assert summary.monthly.activities == [1, 0, 2, 0, 0, 0]
      assert summary.monthly.incidents == [0, 0, 1, 0, 0, 0]
    end

    test "every attended hour a month, by kind, for all 12 months" do
      rows = [
        row(~U[2026-03-10 23:00:00Z], 3, kind: "incident"),
        row(~U[2026-03-17 23:00:00Z], 2, tags: []),
        row(~U[2026-04-07 23:00:00Z], 1, kind: "event")
      ]

      columns = MemberYear.summary(rows, [], 2026, @now, @tz, @tags).hour_columns

      assert length(columns) == 12
      march = Enum.at(columns, 2)
      assert march.label == "Mar"
      assert march.values == %{incident: 3, exercise: 2}
      assert march.tip == "March 2026\nIncidents: 3 hours\nExercises: 2 hours"
      assert Enum.at(columns, 3).values == %{event: 1}
      assert Enum.at(columns, 0).values == %{}
    end
  end
end
