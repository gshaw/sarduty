defmodule Service.DayRangeTest do
  use ExUnit.Case, async: true

  alias Service.DayRange

  test "around runs from midnight days before to midnight days after, in the team's zone" do
    # 8 pm on October 6 in Vancouver is already October 7 in UTC.
    assert DayRange.around(~U[2026-10-07 03:00:00Z], "America/Vancouver", 7) ==
             {~N[2026-09-29 07:00:00], ~N[2026-10-14 07:00:00]}
  end

  test "around follows the clock change" do
    # Toronto's clocks go back on November 1, 2026, so the last midnight is an
    # hour later in UTC.
    assert DayRange.around(~U[2026-10-30 19:00:00Z], "America/Toronto", 7) ==
             {~N[2026-10-23 04:00:00], ~N[2026-11-07 05:00:00]}
  end
end
