defmodule Service.PeriodTest do
  use ExUnit.Case, async: true

  alias Service.Period

  @tz "America/Vancouver"

  test "letter season is January to April in the team's zone" do
    assert Period.letter_season?(~U[2026-04-30 20:00:00Z], @tz)
    refute Period.letter_season?(~U[2026-05-01 08:00:00Z], @tz)
    # Still December 31 in Vancouver.
    refute Period.letter_season?(~U[2026-01-01 07:00:00Z], @tz)
  end

  test "the open years are this year, and last year too in letter season" do
    assert Period.open_years(~U[2026-03-15 18:00:00Z], @tz) == [2025, 2026]
    assert Period.open_years(~U[2026-10-17 18:00:00Z], @tz) == [2026]
  end

  test "the open years start on January 1 of the oldest, in the team's zone" do
    assert Period.open_years_start(~U[2026-03-15 18:00:00Z], @tz) == ~U[2025-01-01 08:00:00Z]
    assert Period.open_years_start(~U[2026-10-17 18:00:00Z], @tz) == ~U[2026-01-01 08:00:00Z]
  end

  describe "a filter's period" do
    @filter_now ~U[2026-10-18 20:30:15.123456Z]

    test "a rolling period is today and that many days before it, whole days (#784)" do
      assert Service.Period.bounds("90d", "America/Vancouver", @filter_now) ==
               {~U[2026-07-20 07:00:00Z], ~U[2026-10-19 07:00:00Z]}
    end

    test "a year is the calendar year in the team's time zone" do
      assert Service.Period.bounds("2026", "America/Vancouver", @filter_now) ==
               {~U[2026-01-01 08:00:00Z], ~U[2027-01-01 07:00:00Z]}

      assert Service.Period.bounds(2026, "America/Vancouver", @filter_now) ==
               {~U[2026-01-01 08:00:00Z], ~U[2027-01-01 07:00:00Z]}
    end
  end

  describe "the last n months (#1116)" do
    test "are whole calendar months, this one included, in the team's zone" do
      november = ~U[2026-11-25 20:00:00Z]
      assert Period.month_dates(3, november, @tz) == {~D[2026-09-01], ~D[2026-11-30]}
      assert Period.month_dates(1, november, @tz) == {~D[2026-11-01], ~D[2026-11-30]}

      assert Period.month_dates(12, ~U[2027-01-15 20:00:00Z], @tz) ==
               {~D[2026-02-01], ~D[2027-01-31]}

      # Still October 31 in Vancouver.
      assert Period.month_dates(1, ~U[2026-11-01 05:00:00Z], @tz) ==
               {~D[2026-10-01], ~D[2026-10-31]}
    end

    test "are written mo, never m, and a filter's days period doesn't take them" do
      assert Period.month_kinds() == [
               {"This month", "1mo"},
               {"Last 3 months", "3mo"},
               {"Last 6 months", "6mo"},
               {"Last 12 months", "12mo"}
             ]

      assert Period.month_period?("3mo")
      refute Period.month_period?("3m")
      refute Period.valid?("3mo")
      assert Period.valid?("90d")
    end
  end
end
