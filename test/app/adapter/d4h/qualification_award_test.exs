defmodule App.Adapter.D4H.QualificationAwardTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.QualificationAward

  # Toronto keeps daylight saving time, so its midnight moves between 04:00 and 05:00 UTC.
  @tz "America/Toronto"

  test "an award D4H keeps at midnight UTC starts on that date, not the day before here" do
    award = %QualificationAward{starts_at: ~U[2026-10-18 00:00:00Z]}

    assert QualificationAward.starts_on?(award, ~D[2026-10-18])
    refute QualificationAward.starts_on?(award, ~D[2026-10-17])
  end

  test "an award SAR Duty sends, at midnight on the team's clock, starts on that date" do
    for date <- [~D[2026-07-01], ~D[2026-11-15]] do
      starts_at = Service.Convert.local_to_utc(date, ~T[00:00:00], @tz)
      award = %QualificationAward{starts_at: starts_at}

      assert QualificationAward.starts_on?(award, date)
      refute QualificationAward.starts_on?(award, Date.add(date, -1))
    end
  end

  test "an award with no start starts on no day" do
    refute QualificationAward.starts_on?(%QualificationAward{starts_at: nil}, ~D[2026-10-18])
  end
end
