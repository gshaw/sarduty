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

  test "days until rounds up, so tomorrow afternoon is 1 day and past is 0 or less" do
    now = ~U[2026-10-20 19:00:00Z]

    assert Service.Convert.days_until(~U[2026-10-21 15:00:00Z], now) == 1
    assert Service.Convert.days_until(~U[2026-12-19 19:00:00Z], now) == 60
    assert Service.Convert.days_until(~U[2026-12-19 19:00:01Z], now) == 61
    assert Service.Convert.days_until(now, now) == 0
    assert Service.Convert.days_until(~U[2026-10-18 19:00:00Z], now) == -2
  end

  test "days later counts calendar days in the zone, like a ticket's +1" do
    zone = "America/Vancouver"
    start = ~U[2026-09-04 06:00:00Z]

    assert Service.Convert.days_later(start, ~U[2026-09-04 09:00:00Z], zone) == 1
    assert Service.Convert.days_later(start, ~U[2026-09-04 06:30:00Z], zone) == 0
    assert Service.Convert.days_later(start, ~U[2026-09-05 08:00:00Z], zone) == 2
    assert Service.Convert.days_later(start, nil, zone) == 0
  end

  test "a duration reads hours and minutes; a bare number is hours up to 24, then minutes" do
    for {text, minutes} <- [
          {"45m", 45},
          {"45 min", 45},
          {"2h", 120},
          {"2.5h", 150},
          {"2.5 hours", 150},
          {".25h", 15},
          {"1h 30m", 90},
          {"1h30", 90},
          {"1:30", 90},
          {"3", 180},
          {"24", 1440},
          {"25", 25},
          {"45", 45},
          {" 1.5 ", 90},
          {"2H", 120}
        ],
        do: assert(Service.Convert.parse_duration(text) == minutes, text)

    for text <- ["", "abc", "1:75", "2h 30h", "-1", "1.5m"],
        do: assert(Service.Convert.parse_duration(text) == nil, text)
  end

  test "a duration box shows minutes as parse_duration/1 reads them back" do
    for minutes <- [15, 60, 90, 150, 480, 1440],
        do:
          assert(
            minutes |> Service.Convert.duration_text() |> Service.Convert.parse_duration() ==
              minutes
          )

    assert Service.Convert.duration_text(90) == "1h 30m"
  end
end
