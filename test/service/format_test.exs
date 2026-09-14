defmodule Service.FormatTest do
  use ExUnit.Case, async: true

  alias Service.Format

  describe "days_ago/3" do
    # 9 a.m. on September 14 in Vancouver.
    @now ~U[2026-09-14 16:00:00Z]
    @zone "America/Vancouver"

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
