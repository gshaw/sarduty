defmodule Service.FormatTest do
  use ExUnit.Case, async: true

  alias Service.Format

  # 9 a.m. on September 14 in Vancouver.
  @now ~U[2026-09-14 16:00:00Z]
  @zone "America/Vancouver"

  test "chart labels: numbers with separators, whole hours, and plain dates" do
    assert Format.number(7) == "7"
    assert Format.number(1204) == "1,204"
    assert Format.number(-1_234_567) == "-1,234,567"
    assert Format.number(12.6) == "13"
    assert Format.hours(72_299) == "1,204h"
    assert Format.day(~D[2025-09-28]) == "Sep 28, 2025"
    assert Format.month_short(~D[2025-09-01]) == "Sep"
  end

  test "quantities: days, km, tenths, and how long a job took" do
    assert Format.days(1) == "1 day"
    assert Format.days(0) == "0 days"
    assert Format.days(30) == "30 days"
    assert Format.days(1095) == "1,095 days"
    assert Format.km(42) == "42 km"
    assert Format.km(1204.4) == "1,204 km"
    assert Format.tenths(1.5) == "1.5"
    assert Format.tenths(2) == "2.0"
    assert Format.run_time(850) == "850 ms"
    assert Format.run_time(4_200) == "4.2 s"
    assert Format.run_time(210_000) == "3.5 min"
  end

  test "duration: hours and minutes, whole hours spelled out, minutes alone under an hour" do
    assert Format.duration(212 * 60 + 30) == "212h 30m"
    assert Format.duration(18 * 60 + 5) == "18h 5m"
    assert Format.duration(202 * 60) == "202 hours"
    assert Format.duration(60) == "1 hour"
    assert Format.duration(45) == "45 min"
    assert Format.duration(0) == "0 hours"
    assert Format.duration(1204 * 60 + 30) == "1,204h 30m"
    assert Format.duration(89.6) == "1h 30m"
  end

  describe "minutes_ago/3" do
    test "counts minutes, then hours, then gives the time" do
      assert @now |> DateTime.add(-30, :second) |> Format.minutes_ago(@now, @zone) == "just now"
      assert @now |> DateTime.add(-4, :minute) |> Format.minutes_ago(@now, @zone) == "4 min ago"
      assert @now |> DateTime.add(-61, :minute) |> Format.minutes_ago(@now, @zone) == "1 hour ago"
      assert @now |> DateTime.add(-5, :hour) |> Format.minutes_ago(@now, @zone) == "5 hours ago"
      assert @now |> DateTime.add(-2, :day) |> Format.minutes_ago(@now, @zone) =~ "2026"
      assert Format.minutes_ago(nil, @now, @zone) == nil
    end
  end

  describe "day_coming_up/3 and starts_in/2" do
    test "names today and tomorrow in the team's zone, then the date" do
      # 11 p.m. on the 14th in Vancouver, though already the 15th in UTC.
      assert Format.day_coming_up(~U[2026-09-15 06:00:00Z], @now, @zone) == "Today"
      assert Format.day_coming_up(~U[2026-09-15 16:00:00Z], @now, @zone) == "Tomorrow"
      assert Format.day_coming_up(~U[2026-09-19 16:00:00Z], @now, @zone) == "Sat Sep 19"
    end

    test "counts minutes, then hours, before and after the start" do
      assert @now |> DateTime.add(25, :minute) |> Format.starts_in(@now) == "in 25 min"
      assert @now |> DateTime.add(61, :minute) |> Format.starts_in(@now) == "in 1 hour"
      assert @now |> DateTime.add(-40, :minute) |> Format.starts_in(@now) == "started 40 min ago"
      assert @now |> DateTime.add(-3, :hour) |> Format.starts_in(@now) == "started 3 hours ago"
    end
  end

  describe "days_ago/3" do
    test "counts calendar days in the team's zone, not UTC" do
      # 11 p.m. on the 13th in Vancouver, though already the 14th in UTC.
      assert Format.days_ago(~U[2026-09-14 06:00:00Z], @now, @zone) == "Yesterday"
      assert Format.days_ago(~U[2026-09-14 08:00:00Z], @now, @zone) == "Today"
    end

    test "counts days for the first six weeks, then months" do
      assert Format.days_ago(~U[2026-09-02 16:00:00Z], @now, @zone) == "12 days ago"
      assert Format.days_ago(~U[2026-05-14 16:00:00Z], @now, @zone) == "4 months ago"
    end

    test "is blank for a user never seen" do
      assert Format.days_ago(nil, @now, @zone) == nil
    end
  end
end
