defmodule Service.DayRangeTest do
  use ExUnit.Case, async: true

  alias Service.DayRange

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
