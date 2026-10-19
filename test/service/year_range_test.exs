defmodule Service.YearRangeTest do
  use ExUnit.Case, async: true

  alias Service.YearRange

  test "bounds are the team's midnights in UTC" do
    assert YearRange.bounds(2025, "America/Vancouver") ==
             {~U[2025-01-01 08:00:00Z], ~U[2026-01-01 08:00:00Z]}

    assert YearRange.bounds("2025", "America/Halifax") ==
             {~U[2025-01-01 04:00:00Z], ~U[2026-01-01 04:00:00Z]}
  end

  test "8 pm on December 31 in Vancouver is in that year" do
    {start, finish} = YearRange.bounds(2025, "America/Vancouver")
    eight_pm = ~U[2026-01-01 04:00:00Z]

    assert DateTime.compare(eight_pm, start) == :gt
    assert DateTime.compare(eight_pm, finish) == :lt
    assert YearRange.year_in(~U[2026-01-01 04:00:00Z], "America/Vancouver") == 2025
  end

  test "years runs newest first, in the team's zone" do
    assert YearRange.years(
             ~U[2023-01-01 07:00:00Z],
             ~U[2026-01-01 04:00:00Z],
             "America/Vancouver"
           ) == [2025, 2024, 2023, 2022]
  end

  test "years is empty with no times" do
    assert YearRange.years(nil, nil, "America/Vancouver") == []
  end
end
