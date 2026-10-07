defmodule App.Operation.CountTaxCreditHoursTest do
  use ExUnit.Case, async: true

  alias App.Operation.CountTaxCreditHours

  @primary ["Primary Hours"]
  @secondary ["Secondary Hours"]
  @timezone "America/Vancouver"

  defp row(started_at, finished_at, tags, attrs \\ %{}) do
    duration =
      if started_at && finished_at, do: div(DateTime.diff(finished_at, started_at), 60), else: 0

    Map.merge(
      %{
        member_id: 1,
        started_at: started_at,
        finished_at: finished_at,
        duration_in_minutes: duration,
        tags: tags
      },
      attrs
    )
  end

  defp hours(rows, year \\ 2025, member_id \\ 1) do
    rows |> CountTaxCreditHours.count(year, @timezone) |> CountTaxCreditHours.get(member_id)
  end

  defp minutes(rows, year \\ 2025) do
    %{primary_minutes: primary, secondary_minutes: secondary} = hours(rows, year)
    {primary, secondary}
  end

  test "a member with no rows has no hours" do
    assert hours([]) == %{primary_minutes: 0, secondary_minutes: 0, total_minutes: 0}
  end

  test "adds primary and secondary into the total" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 20:00:00Z], @primary),
      row(~U[2025-03-02 17:00:00Z], ~U[2025-03-02 18:30:00Z], @secondary)
    ]

    assert hours(rows) == %{primary_minutes: 180, secondary_minutes: 90, total_minutes: 270}
  end

  test "a multi-day shift on one activity counts every day" do
    # One row per day of a three-day search, as D4H records a shift.
    rows = [
      row(~U[2025-07-10 15:00:00Z], ~U[2025-07-11 03:00:00Z], @primary),
      row(~U[2025-07-11 15:00:00Z], ~U[2025-07-12 03:00:00Z], @primary),
      row(~U[2025-07-12 15:00:00Z], ~U[2025-07-12 21:00:00Z], @primary)
    ]

    assert minutes(rows) == {30 * 60, 0}
  end

  test "counts the row's own times, not D4H's duration" do
    # D4H's duration says 4 hours; the row's times say 2.
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 19:00:00Z], @primary, %{
        duration_in_minutes: 240
      })
    ]

    assert minutes(rows) == {120, 0}
  end

  test "falls back to D4H's duration when the finish is missing" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], nil, @primary, %{duration_in_minutes: 45}),
      row(~U[2025-03-02 17:00:00Z], nil, @secondary, %{duration_in_minutes: nil})
    ]

    assert minutes(rows) == {45, 0}
  end

  test "a zero-length row counts nothing" do
    rows = [row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 17:00:00Z], @primary)]
    assert minutes(rows) == {0, 0}
  end

  test "a row that finishes before it starts counts nothing" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 15:00:00Z], @primary, %{
        duration_in_minutes: 120
      })
    ]

    assert minutes(rows) == {0, 0}
  end

  test "a row over 24 hours counts in full" do
    rows = [row(~U[2025-08-01 15:00:00Z], ~U[2025-08-03 15:00:00Z], @primary)]
    assert minutes(rows) == {48 * 60, 0}
  end

  test "overlapping rows of one kind count each minute once" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 20:00:00Z], @primary),
      row(~U[2025-03-01 19:00:00Z], ~U[2025-03-01 21:00:00Z], @primary),
      # Entirely inside the first.
      row(~U[2025-03-01 17:30:00Z], ~U[2025-03-01 18:00:00Z], @primary)
    ]

    assert minutes(rows) == {4 * 60, 0}
  end

  test "rows that only touch both count in full" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 19:00:00Z], @secondary),
      row(~U[2025-03-01 19:00:00Z], ~U[2025-03-01 21:00:00Z], @secondary)
    ]

    assert minutes(rows) == {0, 4 * 60}
  end

  test "where primary and secondary overlap, the overlap is primary" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 20:00:00Z], @primary),
      # An hour before, an hour during, and an hour after the primary row.
      row(~U[2025-03-01 16:00:00Z], ~U[2025-03-01 21:00:00Z], @secondary)
    ]

    assert minutes(rows) == {180, 120}
  end

  test "a secondary row inside a primary row adds nothing" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 20:00:00Z], @primary),
      row(~U[2025-03-01 18:00:00Z], ~U[2025-03-01 19:00:00Z], @secondary)
    ]

    assert minutes(rows) == {180, 0}
  end

  test "rows of different members never merge" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 20:00:00Z], @primary),
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 20:00:00Z], @primary, %{member_id: 2})
    ]

    assert hours(rows, 2025, 1).primary_minutes == 180
    assert hours(rows, 2025, 2).primary_minutes == 180
  end

  test "an activity with neither tag counts nothing" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 20:00:00Z], ["Social"]),
      row(~U[2025-03-02 17:00:00Z], ~U[2025-03-02 20:00:00Z], []),
      row(~U[2025-03-03 17:00:00Z], ~U[2025-03-03 20:00:00Z], nil)
    ]

    assert minutes(rows) == {0, 0}
  end

  test "an activity with both tags counts as primary, once" do
    rows = [row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 20:00:00Z], @primary ++ @secondary)]
    assert minutes(rows) == {180, 0}
  end

  test "8 pm on December 31 in the team's time zone counts toward that year" do
    # 20:00 December 31, 2025 in Vancouver.
    rows = [row(~U[2026-01-01 04:00:00Z], ~U[2026-01-01 05:00:00Z], @primary)]

    assert minutes(rows, 2025) == {60, 0}
    assert minutes(rows, 2026) == {0, 0}
  end

  test "midnight on January 1 in the team's time zone starts the year" do
    rows = [row(~U[2026-01-01 08:00:00Z], ~U[2026-01-01 09:00:00Z], @primary)]

    assert minutes(rows, 2025) == {0, 0}
    assert minutes(rows, 2026) == {60, 0}
  end

  test "a shift across New Year counts toward the year it started" do
    # 22:00 December 31, 2025 to 02:00 January 1, 2026 in Vancouver.
    rows = [row(~U[2026-01-01 06:00:00Z], ~U[2026-01-01 10:00:00Z], @primary)]

    assert minutes(rows, 2025) == {240, 0}
    assert minutes(rows, 2026) == {0, 0}
  end
end
