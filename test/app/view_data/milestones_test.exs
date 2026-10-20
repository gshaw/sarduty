defmodule App.ViewData.MilestonesTest do
  use ExUnit.Case, async: true

  alias App.ViewData.Milestones

  @tz "America/Vancouver"
  @now ~U[2026-10-20 19:00:00Z]

  defp row(started_at, kind, minutes, title \\ "Activity") do
    %{
      started_at: started_at,
      finished_at: DateTime.add(started_at, minutes * 60),
      duration_in_minutes: nil,
      activity: %{activity_kind: kind, title: title}
    }
  end

  defp day(month, day), do: 2026 |> Date.new!(month, day) |> DateTime.new!(~T[18:00:00])

  defp summary(milestones), do: Enum.map(milestones, &{&1.kind, &1.count, &1.on})

  test "the lines: fixed ones, then steps" do
    assert Milestones.lines(:hours, 3500) == [100, 250, 500, 1000, 2000, 3000]
    assert Milestones.lines(:years, 21) == [1, 5, 10, 15, 20]
    assert Milestones.lines(:incidents, 99) == [1, 10, 25, 50]
    assert Milestones.lines(:incidents, 300) == [1, 10, 25, 50, 100, 200, 300]
    assert Milestones.lines(:hours, 99) == []
  end

  test "hours are dated by the activity that crossed the line, even one that crosses two" do
    rows = [
      row(~U[2026-01-10 18:00:00Z], "exercise", 99 * 60),
      # 99 hours, then 160 more: past 100 and 250 at once.
      row(~U[2026-02-10 18:00:00Z], "exercise", 160 * 60, "Long search")
    ]

    assert [
             %{kind: :hours, count: 250, on: ~D[2026-02-10], activity: %{title: "Long search"}},
             %{kind: :hours, count: 100, on: ~D[2026-02-10]}
           ] = Milestones.build(rows, nil, [], @now, @tz)
  end

  test "every attended activity counts toward hours, in start order whatever order they come in" do
    rows = [
      row(~U[2026-03-01 18:00:00Z], "event", 50 * 60, "Second"),
      row(~U[2026-02-01 18:00:00Z], "event", 50 * 60, "First")
    ]

    assert [%{kind: :hours, count: 100, activity: %{title: "Second"}}] =
             Milestones.build(rows, nil, [], @now, @tz)
  end

  test "incidents: the first, then 10, dated in the team's time zone" do
    # 23:30 on Mar 31 in Vancouver.
    first = row(~U[2026-04-01 06:30:00Z], "incident", 60)

    exercises =
      for d <- 1..5, do: row(day(5, d), "exercise", 60)

    more =
      for d <- 1..9, do: row(day(6, d), "incident", 60)

    assert first
           |> List.wrap()
           |> Enum.concat(exercises ++ more)
           |> Milestones.build(nil, [], @now, @tz)
           |> summary() == [
             {:incidents, 10, ~D[2026-06-09]},
             {:incidents, 1, ~D[2026-03-31]}
           ]
  end

  test "years come on each anniversary that has passed, from the day they joined" do
    joined = ~U[2016-10-21 05:00:00Z]

    # Joined Oct 20, 2016 in Vancouver: 10 years today, not 11 months.
    assert summary(Milestones.build([], joined, [], @now, @tz)) == [
             {:years, 10, ~D[2026-10-20]},
             {:years, 5, ~D[2021-10-20]},
             {:years, 1, ~D[2017-10-20]}
           ]

    assert Milestones.build([], ~U[2026-03-01 19:00:00Z], [], @now, @tz) == []
    assert Milestones.build([], nil, [], @now, @tz) == []
  end

  describe "years without away periods" do
    # Joined Oct 20, 2016 in Vancouver.
    @joined ~U[2016-10-21 05:00:00Z]

    defp away(starts_on, ends_on), do: %{starts_on: starts_on, ends_on: ends_on}

    defp years(away_periods),
      do: summary(Milestones.build([], @joined, away_periods, @now, @tz))

    test "a gap before an anniversary moves it by the gap's days; one after doesn't" do
      # Left for 2018 and 2019, 730 days, then rejoined.
      assert years([away(~D[2018-01-01], ~D[2019-12-31])]) == [
               {:years, 5, ~D[2023-10-20]},
               {:years, 1, ~D[2017-10-20]}
             ]
    end

    test "overlapping periods count once" do
      assert years([away(~D[2018-07-01], ~D[2019-12-31]), away(~D[2018-01-01], ~D[2018-12-31])]) ==
               years([away(~D[2018-01-01], ~D[2019-12-31])])
    end

    test "a gap the push reaches moves it too" do
      # 10 days away moves the first year to Oct 30, which takes in 2 more days.
      assert [{:years, 1, ~D[2017-11-01]} | _] =
               [away(~D[2017-10-25], ~D[2017-10-26]), away(~D[2017-10-01], ~D[2017-10-10])]
               |> years()
               |> Enum.reverse()
    end

    test "leave going on today holds off the next one" do
      assert years([away(~D[2026-09-01], ~D[2027-03-31])]) == [
               {:years, 5, ~D[2021-10-20]},
               {:years, 1, ~D[2017-10-20]}
             ]
    end

    test "days away before they joined don't count" do
      assert years([away(~D[2015-01-01], ~D[2016-10-19])]) == years([])
    end
  end

  test "a leap day anniversary falls on Feb 28" do
    assert [%{on: ~D[2025-02-28]}] = Milestones.build([], ~U[2024-02-29 20:00:00Z], [], @now, @tz)
  end

  test "newest first, and years before hours on the same day" do
    rows = [row(~U[2017-10-20 18:00:00Z], "incident", 100 * 60)]

    assert summary(
             Milestones.build(rows, ~U[2016-10-20 19:00:00Z], [], ~U[2018-01-01 19:00:00Z], @tz)
           ) == [
             {:years, 1, ~D[2017-10-20]},
             {:hours, 100, ~D[2017-10-20]},
             {:incidents, 1, ~D[2017-10-20]}
           ]
  end
end
