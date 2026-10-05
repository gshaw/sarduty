defmodule App.Operation.RecordAttendanceScanTest do
  use ExUnit.Case, async: true

  alias App.Operation.RecordAttendanceScan

  # 17:30 UTC is 10:30 in Vancouver in October.
  @now ~U[2026-10-10 17:30:00Z]

  test "a typed time is that time today in the team's time zone" do
    assert RecordAttendanceScan.override_at("09:15", @now, "America/Vancouver") ==
             {:ok, ~U[2026-10-10 16:15:00.000000Z]}

    assert RecordAttendanceScan.override_at("915", @now, "America/Vancouver") ==
             {:ok, ~U[2026-10-10 16:15:00.000000Z]}
  end

  test "nothing typed means the moment of the scan" do
    assert RecordAttendanceScan.override_at("", @now, "America/Vancouver") == {:ok, nil}
    assert RecordAttendanceScan.override_at(nil, @now, "America/Vancouver") == {:ok, nil}
  end

  test "text that isn't a time is refused" do
    assert RecordAttendanceScan.override_at("9am", @now, "America/Vancouver") == :error
    assert RecordAttendanceScan.override_at("25:00", @now, "America/Vancouver") == :error
  end
end
