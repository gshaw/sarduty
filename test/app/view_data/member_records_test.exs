defmodule App.ViewData.MemberRecordsTest do
  use ExUnit.Case, async: true

  alias App.ViewData.MemberRecords

  @now ~U[2026-10-09 12:00:00Z]

  defp award(qualification_id, title, ends_at, starts_at \\ nil) do
    %{
      qualification_id: qualification_id,
      qualification: %{title: title},
      starts_at: starts_at,
      ends_at: ends_at
    }
  end

  defp titles(rows), do: Enum.map(rows, &{&1.status, &1.award.qualification.title})

  describe "qualification_rows/2" do
    test "current come soonest end first, then by title, no end last; expired most recent first" do
      awards = [
        award(1, "Never", nil),
        award(2, "Rope", ~U[2027-09-01 00:00:00Z]),
        award(3, "Avalanche", ~U[2027-09-01 00:00:00Z]),
        award(4, "Soon", ~U[2026-11-01 00:00:00Z]),
        award(5, "Old", ~U[2020-01-01 00:00:00Z]),
        award(6, "Recent", ~U[2026-09-01 00:00:00Z])
      ]

      assert awards |> MemberRecords.qualification_rows(@now) |> titles() == [
               expiring: "Soon",
               current: "Avalanche",
               current: "Rope",
               current: "Never",
               expired: "Recent",
               expired: "Old"
             ]

      assert MemberRecords.qualification_rows([], @now) == []
    end

    test "expiring holds an award ending on the window's last second, and one ending now is expired" do
      sixty = DateTime.add(@now, 60, :day)

      awards = [
        award(1, "At 60", sixty),
        award(2, "Past 60", DateTime.add(sixty, 1)),
        award(3, "Now", @now)
      ]

      rows = MemberRecords.qualification_rows(awards, @now)

      assert titles(rows) == [expiring: "At 60", current: "Past 60", expired: "Now"]
      assert Enum.map(rows, & &1.days_left) == [60, 61, 0]
    end

    test "a renewal is one row, carrying the awards it replaced" do
      awards = [
        award(1, "First Aid", ~U[2022-03-01 00:00:00Z], ~U[2019-03-01 00:00:00Z]),
        award(1, "First Aid", ~U[2028-03-01 00:00:00Z], ~U[2025-03-01 00:00:00Z]),
        award(1, "First Aid", ~U[2025-03-01 00:00:00Z], ~U[2022-03-01 00:00:00Z]),
        award(2, "Rope", ~U[2027-01-01 00:00:00Z]),
        award(2, "Rope", nil)
      ]

      [first_aid, rope] = MemberRecords.qualification_rows(awards, @now)

      assert first_aid.status == :current
      assert first_aid.award.ends_at == ~U[2028-03-01 00:00:00Z]

      assert Enum.map(first_aid.earlier, & &1.ends_at) == [
               ~U[2025-03-01 00:00:00Z],
               ~U[2022-03-01 00:00:00Z]
             ]

      assert first_aid.first_started_at == ~U[2019-03-01 00:00:00Z]

      # No end is the latest, and with no start there is no first start.
      assert rope.award.ends_at == nil
      assert Enum.map(rope.earlier, & &1.ends_at) == [~U[2027-01-01 00:00:00Z]]
      assert rope.first_started_at == nil
    end

    test "of two awards with no end, the one that started last is the latest" do
      awards = [
        award(1, "Avalanche", nil),
        award(1, "Avalanche", nil, ~U[2018-02-01 00:00:00Z]),
        award(1, "Avalanche", nil, ~U[2019-02-01 00:00:00Z])
      ]

      [avalanche] = MemberRecords.qualification_rows(awards, @now)
      assert avalanche.award.starts_at == ~U[2019-02-01 00:00:00Z]
      assert Enum.map(avalanche.earlier, & &1.starts_at) == [~U[2018-02-01 00:00:00Z], nil]
      assert avalanche.first_started_at == ~U[2018-02-01 00:00:00Z]
    end

    test "an expired qualification renewed in the past is expired, held from its first start" do
      awards = [
        award(1, "Rope", ~U[2024-09-01 00:00:00Z], ~U[2021-09-01 00:00:00Z]),
        award(1, "Rope", ~U[2021-09-01 00:00:00Z], ~U[2019-03-01 00:00:00Z])
      ]

      [rope] = MemberRecords.qualification_rows(awards, @now)
      assert rope.status == :expired
      assert rope.award.ends_at == ~U[2024-09-01 00:00:00Z]
      assert rope.first_started_at == ~U[2019-03-01 00:00:00Z]
    end
  end

  describe "minutes/1" do
    test "uses the member's own times, else D4H's duration" do
      timed = %{
        started_at: ~U[2026-01-01 10:00:00Z],
        finished_at: ~U[2026-01-01 12:30:00Z],
        duration_in_minutes: 60
      }

      assert MemberRecords.minutes(timed) == 150
      assert MemberRecords.minutes(%{timed | finished_at: nil}) == 60

      assert MemberRecords.minutes(%{started_at: nil, finished_at: nil, duration_in_minutes: nil}) ==
               0
    end
  end

  describe "hours_kind/2 and other_minutes/2" do
    @hours_tags %{primary: "Primary Hours", secondary: "Secondary Hours", other: nil}

    defp row(tags, minutes),
      do: %{
        activity: %{tags: tags},
        started_at: nil,
        finished_at: nil,
        duration_in_minutes: minutes
      }

    test "an activity counts for the hours its tags say, primary first, else other" do
      kind = fn tags -> tags |> row(0) |> MemberRecords.hours_kind(@hours_tags) end

      assert kind.(["Primary Hours", "Secondary Hours"]) == :primary
      assert kind.(["Secondary Hours"]) == :secondary
      assert kind.(nil) == :other
    end

    test "other is the time on activities with neither hours tag" do
      rows = [row(["Primary Hours"], 60), row([], 45), row(["Social"], 30)]
      assert MemberRecords.other_minutes(rows, @hours_tags) == 75
    end
  end
end
