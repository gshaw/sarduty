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

  defp titles(groups),
    do:
      Enum.map(groups, fn {group, rows} ->
        {group, Enum.map(rows, & &1.award.qualification.title)}
      end)

  describe "group_awards/2" do
    test "puts each qualification in one group by when it ends, leaving out empty groups" do
      awards = [
        award(1, "Never", nil),
        award(2, "Later", ~U[2027-06-01 00:00:00Z]),
        award(3, "Half a year", ~U[2027-02-01 00:00:00Z]),
        award(4, "Soon", ~U[2026-11-01 00:00:00Z]),
        award(5, "Gone", ~U[2026-09-01 00:00:00Z])
      ]

      assert awards |> MemberRecords.group_awards(@now) |> titles() == [
               within_60_days: ["Soon"],
               within_180_days: ["Half a year"],
               later: ["Later"],
               never: ["Never"],
               expired: ["Gone"]
             ]

      assert [award(1, "Never", nil)] |> MemberRecords.group_awards(@now) |> titles() == [
               never: ["Never"]
             ]

      assert MemberRecords.group_awards([], @now) == []
    end

    test "a window holds an award ending on its last second, and an award ending now is expired" do
      sixty = DateTime.add(@now, 60, :day)
      one_eighty = DateTime.add(@now, 180, :day)

      awards = [
        award(1, "At 60", sixty),
        award(2, "Past 60", DateTime.add(sixty, 1)),
        award(3, "At 180", one_eighty),
        award(4, "Past 180", DateTime.add(one_eighty, 1)),
        award(5, "Now", @now)
      ]

      assert awards |> MemberRecords.group_awards(@now) |> titles() == [
               within_60_days: ["At 60"],
               within_180_days: ["Past 60", "At 180"],
               later: ["Past 180"],
               expired: ["Now"]
             ]
    end

    test "current come soonest end first, then by title; expired most recent first" do
      awards = [
        award(1, "Rope", ~U[2027-09-01 00:00:00Z]),
        award(2, "Avalanche", ~U[2027-09-01 00:00:00Z]),
        award(3, "First Aid", ~U[2027-07-01 00:00:00Z]),
        award(4, "Old", ~U[2020-01-01 00:00:00Z]),
        award(5, "Recent", ~U[2026-09-01 00:00:00Z])
      ]

      assert awards |> MemberRecords.group_awards(@now) |> titles() == [
               later: ["First Aid", "Avalanche", "Rope"],
               expired: ["Recent", "Old"]
             ]
    end

    test "a renewal is one row in its current group, carrying the awards it replaced" do
      awards = [
        award(1, "First Aid", ~U[2022-03-01 00:00:00Z], ~U[2019-03-01 00:00:00Z]),
        award(1, "First Aid", ~U[2028-03-01 00:00:00Z], ~U[2025-03-01 00:00:00Z]),
        award(1, "First Aid", ~U[2025-03-01 00:00:00Z], ~U[2022-03-01 00:00:00Z]),
        award(2, "Rope", ~U[2027-01-01 00:00:00Z]),
        award(2, "Rope", nil)
      ]

      [later: [first_aid], never: [rope]] = MemberRecords.group_awards(awards, @now)

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

    test "an expired qualification renewed in the past is expired, held from its first start" do
      awards = [
        award(1, "Rope", ~U[2024-09-01 00:00:00Z], ~U[2021-09-01 00:00:00Z]),
        award(1, "Rope", ~U[2021-09-01 00:00:00Z], ~U[2019-03-01 00:00:00Z])
      ]

      [expired: [rope]] = MemberRecords.group_awards(awards, @now)
      assert rope.award.ends_at == ~U[2024-09-01 00:00:00Z]
      assert rope.first_started_at == ~U[2019-03-01 00:00:00Z]
    end
  end

  describe "by_month/2" do
    test "groups by the month in the team's time zone, keeping the order" do
      rows = [
        %{id: 1, started_at: ~U[2026-10-02 18:00:00Z]},
        # 23:30 on Sep 30 in Vancouver.
        %{id: 2, started_at: ~U[2026-10-01 06:30:00Z]},
        %{id: 3, started_at: ~U[2026-09-01 18:00:00Z]},
        %{id: 4, started_at: ~U[2026-06-15 18:00:00Z]}
      ]

      groups = MemberRecords.by_month(rows, "America/Vancouver")

      assert Enum.map(groups, fn {month, rows} -> {month, Enum.map(rows, & &1.id)} end) == [
               {~D[2026-10-01], [1]},
               {~D[2026-09-01], [2, 3]},
               {~D[2026-06-01], [4]}
             ]

      assert MemberRecords.by_month([], "America/Vancouver") == []
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
end
