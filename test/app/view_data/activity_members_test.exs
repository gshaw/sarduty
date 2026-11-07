defmodule App.ViewData.ActivityMembersTest do
  use ExUnit.Case, async: true

  alias App.Model.Attendance
  alias App.Model.Member
  alias App.ViewData.ActivityMembers

  @tz "America/Vancouver"

  defp row(name, status, replied_at \\ nil),
    do: %Attendance{status: status, replied_at: replied_at, member: %Member{name: name}}

  test "signed up first, then can't make it, then no reply, each by name" do
    rows = [
      row("Wren Adams", "requested"),
      row("taylor Brooks", "absent"),
      row("Sam Rivera", "attending"),
      row("Cameron Ruiz", "requested"),
      row("alex Chen", "attending"),
      row("Quinn Laval", "absent")
    ]

    assert rows |> ActivityMembers.sort() |> Enum.map(& &1.member.name) == [
             "alex Chen",
             "Sam Rivera",
             "Quinn Laval",
             "taylor Brooks",
             "Cameron Ruiz",
             "Wren Adams"
           ]
  end

  test "the counts are per status, and a view keeps one" do
    rows = [row("A", "attending"), row("B", "attending"), row("C", "requested")]

    assert ActivityMembers.counts(rows) == %{attending: 2, absent: 0, requested: 1}
    assert rows |> ActivityMembers.only("requested") |> length() == 1
    assert rows |> ActivityMembers.only(nil) |> length() == 3
  end

  test "a reply is new for 24 hours" do
    now = ~U[2026-10-22 16:00:00Z]

    today = row("A", "attending", ~U[2026-10-22 08:12:00Z])
    yesterday = row("B", "attending", ~U[2026-10-21 16:00:00Z])
    no_reply = row("C", "requested")

    assert ActivityMembers.new?(today, now)
    refute ActivityMembers.new?(yesterday, now)
    refute ActivityMembers.new?(no_reply, now)
  end

  # 19:00 in Vancouver is 02:00 UTC the next day: the day is the team's.
  test "a start on the activity's own day, in the team's time zone" do
    activity_start = ~U[2026-10-30 02:00:00Z]

    assert ActivityMembers.same_day?(~U[2026-10-30 03:00:00Z], activity_start, @tz)
    assert ActivityMembers.same_day?(~U[2026-10-29 20:00:00Z], activity_start, @tz)
    refute ActivityMembers.same_day?(~U[2026-10-30 08:00:00Z], activity_start, @tz)
  end

  # The cast's names (App.CoastRange).
  # cspell:ignore Kowal Noor
  describe "shown/4 (#920)" do
    defp member_row(id, name, status),
      do: %Attendance{status: status, member: %Member{id: id, name: name}}

    setup do
      %{
        rows: [
          member_row(1, "Harper Nguyen", "attending"),
          member_row(2, "Dana Kowal", "absent"),
          member_row(3, "Noor Aziz", "requested"),
          member_row(4, "Riley Okafor", "requested")
        ]
      }
    end

    defp names(rows), do: Enum.map(rows, & &1.member.name)

    test "with nothing on, every row in order", %{rows: rows} do
      assert ActivityMembers.shown(rows, nil, nil, nil) == rows
    end

    test "the group, then the status, then the search", %{rows: rows} do
      group = MapSet.new([1, 3, 4])

      assert rows |> ActivityMembers.shown(group, nil, nil) |> names() == [
               "Harper Nguyen",
               "Noor Aziz",
               "Riley Okafor"
             ]

      assert rows |> ActivityMembers.shown(group, "requested", nil) |> names() == [
               "Noor Aziz",
               "Riley Okafor"
             ]

      assert rows |> ActivityMembers.shown(group, "requested", "oka") |> names() == [
               "Riley Okafor"
             ]

      assert rows |> ActivityMembers.shown(group, "absent", nil) == []
    end

    test "search finds the name anywhere, case aside", %{rows: rows} do
      assert rows |> ActivityMembers.shown(nil, nil, "KOW") |> names() == ["Dana Kowal"]

      assert rows |> ActivityMembers.shown(nil, nil, " noor ") |> names() == ["Noor Aziz"]

      assert ActivityMembers.shown(rows, nil, nil, "zed") == []
    end

    test "the tiles count the group's rows, before the status and search", %{rows: rows} do
      in_group = ActivityMembers.in_group(rows, MapSet.new([2, 3]))
      assert ActivityMembers.counts(in_group) == %{attending: 0, absent: 1, requested: 1}
      assert ActivityMembers.in_group(rows, nil) == rows
    end
  end
end
