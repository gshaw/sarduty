defmodule Service.DayRangeTest do
  use ExUnit.Case, async: true

  alias Service.DayRange

  test "around runs from midnight days before to midnight days after, in the team's zone" do
    # 8 pm on October 6 in Vancouver is already October 7 in UTC.
    assert DayRange.around(~U[2026-10-07 03:00:00Z], "America/Vancouver", 7) ==
             {~U[2026-09-29 07:00:00Z], ~U[2026-10-14 07:00:00Z]}
  end

  test "around follows the clock change" do
    # Toronto's clocks go back on November 1, 2026, so the last midnight is an
    # hour later in UTC.
    assert DayRange.around(~U[2026-10-30 19:00:00Z], "America/Toronto", 7) ==
             {~U[2026-10-23 04:00:00Z], ~U[2026-11-07 05:00:00Z]}
  end

  test "last is today and that many days before it, whole days in the team's zone (#784)" do
    # 8 pm on October 6 in Vancouver: the last 30 days are September 6 to October 6.
    assert DayRange.last(~U[2026-10-07 03:00:00Z], "America/Vancouver", 30) ==
             {~U[2026-09-06 07:00:00Z], ~U[2026-10-07 07:00:00Z]}
  end

  test "a day whose midnight the clocks skip starts when they do" do
    # Havana's clocks go from midnight to 1 am on March 8, 2026.
    assert DayRange.start_of_day(~D[2026-03-08], "America/Havana") == ~U[2026-03-08 05:00:00Z]
  end
end
