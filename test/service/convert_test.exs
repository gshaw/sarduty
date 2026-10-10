defmodule Service.ConvertTest do
  use ExUnit.Case, async: true

  alias Service.Convert

  @tz "America/Vancouver"

  test "a wall-clock time in the team's zone is the right UTC time" do
    assert Convert.local_to_utc(~D[2026-01-15], ~T[00:00:00], @tz) == ~U[2026-01-15 08:00:00Z]
    assert Convert.local_to_utc(~D[2026-07-15], ~T[18:30:00], @tz) == ~U[2026-07-16 01:30:00Z]
  end

  test "a skipped time is the time after the gap, and a repeated one the first" do
    # 02:30 on March 8, 2026 never happens in Vancouver; 01:30 on November 1 happens twice.
    assert Convert.local_to_utc(~D[2026-03-08], ~T[02:30:00], @tz) == ~U[2026-03-08 10:00:00Z]
    assert Convert.local_to_utc(~D[2026-11-01], ~T[01:30:00], @tz) == ~U[2026-11-01 08:30:00Z]
  end

  test "a UTC time reads back as the date and time on the team's clock" do
    assert Convert.utc_to_local(~U[2026-07-16 01:30:00Z], @tz) == {~D[2026-07-15], ~T[18:30:00]}
  end

  test "hours a person typed become minutes; blank, words, and negatives are 0" do
    assert Convert.hours_to_minutes("1.5") == 90
    assert Convert.hours_to_minutes(" 2 ") == 120
    assert Convert.hours_to_minutes("") == 0
    assert Convert.hours_to_minutes("two") == 0
    assert Convert.hours_to_minutes("-1") == 0
  end

  test "minutes become hours for a form field" do
    assert Convert.minutes_to_hours(120) == "2"
    assert Convert.minutes_to_hours(90) == "1.5"
    assert Convert.minutes_to_hours(0) == "0"
  end
end
