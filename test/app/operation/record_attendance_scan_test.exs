defmodule App.Operation.RecordAttendanceScanTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Operation.RecordAttendanceScan

  @zone "America/Vancouver"

  # 18:00–21:00 in Vancouver on October 10. Vancouver is UTC-7 in October.
  @evening %Activity{started_at: ~U[2026-10-11 01:00:00Z], finished_at: ~U[2026-10-11 04:00:00Z]}

  # 22:00 on October 10 to 02:00 on October 11 in Vancouver.
  @overnight %Activity{
    started_at: ~U[2026-10-11 05:00:00Z],
    finished_at: ~U[2026-10-11 09:00:00Z]
  }

  # 08:00 on October 10 to 17:00 on October 12 in Vancouver.
  @weekend %Activity{started_at: ~U[2026-10-10 15:00:00Z], finished_at: ~U[2026-10-13 00:00:00Z]}

  defp override_at(text, activity, now),
    do: RecordAttendanceScan.override_at(text, activity, now, @zone)

  test "a typed time during the activity is that time on its day" do
    now = ~U[2026-10-11 02:00:00Z]
    assert override_at("18:15", @evening, now) == {:ok, ~U[2026-10-11 01:15:00.000000Z]}
    assert override_at("1815", @evening, now) == {:ok, ~U[2026-10-11 01:15:00.000000Z]}
  end

  test "a catch-up the next morning lands on the activity's day, not today" do
    next_morning = ~U[2026-10-11 16:00:00Z]
    assert override_at("18:05", @evening, next_morning) == {:ok, ~U[2026-10-11 01:05:00.000000Z]}
    assert override_at("21:10", @evening, next_morning) == {:ok, ~U[2026-10-11 04:10:00.000000Z]}
  end

  test "a catch-up days later lands on the activity's day" do
    week_later = ~U[2026-10-18 16:00:00Z]
    assert override_at("18:05", @evening, week_later) == {:ok, ~U[2026-10-11 01:05:00.000000Z]}
  end

  test "an activity that crosses midnight puts each time on the right side of it" do
    now = ~U[2026-10-11 16:00:00Z]
    # 22:10 on October 10, and 01:50 on October 11.
    assert override_at("22:10", @overnight, now) == {:ok, ~U[2026-10-11 05:10:00.000000Z]}
    assert override_at("01:50", @overnight, now) == {:ok, ~U[2026-10-11 08:50:00.000000Z]}
  end

  test "a time just outside the activity goes on the nearest day" do
    now = ~U[2026-10-11 16:00:00Z]
    # Leaving at 02:30 is 30 minutes after an overnight activity ends.
    assert override_at("02:30", @overnight, now) == {:ok, ~U[2026-10-11 09:30:00.000000Z]}
    # Arriving at 17:30 is 30 minutes before an evening activity starts.
    assert override_at("17:30", @evening, now) == {:ok, ~U[2026-10-11 00:30:00.000000Z]}
  end

  test "on a multi-day activity, the day nearest now wins" do
    second_morning = ~U[2026-10-11 16:10:00Z]

    assert override_at("09:00", @weekend, second_morning) ==
             {:ok, ~U[2026-10-11 16:00:00.000000Z]}
  end

  test "nothing typed means the moment of the scan" do
    assert override_at("", @evening, ~U[2026-10-11 02:00:00Z]) == {:ok, nil}
    assert override_at(nil, @evening, ~U[2026-10-11 02:00:00Z]) == {:ok, nil}
  end

  test "text that isn't a time is refused" do
    assert override_at("9am", @evening, ~U[2026-10-11 02:00:00Z]) == :error
    assert override_at("25:00", @evening, ~U[2026-10-11 02:00:00Z]) == :error
  end
end
