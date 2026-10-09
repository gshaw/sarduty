defmodule App.ViewData.MemberRecordsTest do
  use ExUnit.Case, async: true

  alias App.ViewData.MemberRecords

  @now ~U[2026-10-09 12:00:00Z]

  defp award(qualification_id, title, ends_at) do
    %{qualification_id: qualification_id, qualification: %{title: title}, ends_at: ends_at}
  end

  describe "split_awards/3" do
    test "keeps the latest award of each qualification, a missing end being latest" do
      awards = [
        award(1, "First Aid", ~U[2025-01-01 00:00:00Z]),
        award(1, "First Aid", ~U[2028-01-01 00:00:00Z]),
        award(2, "Rope", ~U[2027-01-01 00:00:00Z]),
        award(2, "Rope", nil)
      ]

      %{current: current, expired: []} = MemberRecords.split_awards(awards, @now, 60)

      assert Enum.map(current, &{&1.award.qualification.title, &1.award.ends_at}) == [
               {"First Aid", ~U[2028-01-01 00:00:00Z]},
               {"Rope", nil}
             ]
    end

    test "current come soonest to expire first and mark the ones within the window" do
      awards = [
        award(1, "Never", nil),
        award(2, "Later", ~U[2027-06-01 00:00:00Z]),
        award(3, "Soon", ~U[2026-11-01 00:00:00Z])
      ]

      %{current: current} = MemberRecords.split_awards(awards, @now, 60)

      assert Enum.map(current, &{&1.award.qualification.title, &1.expiring?}) == [
               {"Soon", true},
               {"Later", false},
               {"Never", false}
             ]
    end

    test "expired come most recently expired first" do
      awards = [
        award(1, "Old", ~U[2020-01-01 00:00:00Z]),
        award(2, "Recent", ~U[2026-09-01 00:00:00Z])
      ]

      %{current: [], expired: expired} = MemberRecords.split_awards(awards, @now, 60)
      assert Enum.map(expired, & &1.award.qualification.title) == ["Recent", "Old"]
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
