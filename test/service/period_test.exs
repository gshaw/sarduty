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

    test "a rolling period ends now and reaches back that many days" do
      assert Service.Period.bounds("90d", "America/Vancouver", @filter_now) ==
               {~U[2026-07-20 20:30:15Z], ~U[2026-10-18 20:30:15Z]}
    end

    test "a year is the calendar year in the team's time zone" do
      assert Service.Period.bounds("2026", "America/Vancouver", @filter_now) ==
               {~U[2026-01-01 08:00:00Z], ~U[2027-01-01 07:00:00Z]}

      assert Service.Period.bounds(2026, "America/Vancouver", @filter_now) ==
               {~U[2026-01-01 08:00:00Z], ~U[2027-01-01 07:00:00Z]}
    end
  end
end
