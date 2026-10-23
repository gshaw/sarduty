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
end
