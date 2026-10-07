defmodule Service.TimeBucketsTest do
  use ExUnit.Case, async: true

  alias Service.TimeBuckets

  @tz "America/Vancouver"

  test "months end with now's month, in the team's zone" do
    # 03:00 UTC on Oct 1 is still September in Vancouver.
    months = TimeBuckets.months(~U[2026-10-01 03:00:00Z], @tz, 3)
    assert months == [~D[2026-07-01], ~D[2026-08-01], ~D[2026-09-01]]
  end

  test "counts by month and key, with empty months kept" do
    rows = [
      {~U[2026-09-10 18:00:00Z], :incident},
      {~U[2026-09-11 18:00:00Z], :incident},
      {~U[2026-10-01 03:00:00Z], :exercise},
      {~U[2025-01-01 00:00:00Z], :incident}
    ]

    months = [~D[2026-08-01], ~D[2026-09-01]]

    assert TimeBuckets.count_by_month(rows, months, @tz) == [
             {~D[2026-08-01], %{}},
             {~D[2026-09-01], %{incident: 2, exercise: 1}}
           ]
  end

  test "week rows put Monday first and count by local hour" do
    # Mon Oct 5, 2026 at 19:30 in Vancouver.
    counts = TimeBuckets.count_by_week_hour([~U[2026-10-06 02:30:00Z]], @tz)
    assert counts == %{{1, 19} => 1}

    rows = TimeBuckets.week_rows(counts)
    assert length(rows) == 7
    assert rows |> hd() |> Enum.at(19) == 1
    assert rows |> List.flatten() |> Enum.sum() == 1
  end

  test "running totals stop at now's month" do
    rows = [{~U[2026-01-15 20:00:00Z], 60}, {~U[2026-03-15 20:00:00Z], 30}]
    totals = TimeBuckets.cumulative_by_month(rows, 2026, ~U[2026-03-20 20:00:00Z], @tz)

    assert Enum.take(totals, 4) == [60, 60, 90, nil]

    assert TimeBuckets.cumulative_by_month(rows, 2025, ~U[2026-03-20 20:00:00Z], @tz) ==
             List.duplicate(0, 12)
  end

  test "shades split the busiest count into quarters" do
    assert TimeBuckets.level(0, 8) == 0
    assert TimeBuckets.level(1, 8) == 1
    assert TimeBuckets.level(4, 8) == 2
    assert TimeBuckets.level(8, 8) == 4
  end
end
