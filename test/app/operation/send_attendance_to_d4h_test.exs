defmodule App.Operation.SendAttendanceToD4HTest do
  use ExUnit.Case, async: true

  alias App.Accounts.User
  alias App.Adapter.D4H.AttendanceInfo
  alias App.Model.Activity
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.SendAttendanceToD4H

  @start ~U[2026-10-10 16:00:00Z]
  @finish ~U[2026-10-10 22:00:00Z]

  defp member(id, name), do: %Member{id: id, d4h_member_id: 1000 + id, name: name}

  defp time(member, notes \\ []),
    do: %{member: member, arrived_at: @start, left_at: @finish, notes: notes}

  defp row(member, status, attrs \\ []) do
    struct(
      %AttendanceInfo{
        d4h_attendance_id: 5000 + member.id,
        d4h_member_id: member.d4h_member_id,
        status: status,
        started_at: @start,
        finished_at: @finish
      },
      attrs
    )
  end

  defp plan(times, rows, members) do
    times
    |> SendAttendanceToD4H.plan(rows, members)
    |> Map.new(&{&1.member.name, &1})
  end

  test "a member who signed up and arrived is marked attending with the door's times" do
    mei = member(1, "Mei")
    late = %{time(mei) | arrived_at: ~U[2026-10-10 16:20:00Z]}

    %{"Mei" => change} = plan([late], [row(mei, "requested")], [mei])

    assert change.action == :update
    assert change.d4h_attendance_id == 5001
    assert change.arrived_at == ~U[2026-10-10 16:20:00Z]
    assert change.selected
  end

  test "a member D4H has no row for is added, never updated" do
    lena = member(2, "Lena")

    assert %{"Lena" => %{action: :create, d4h_attendance_id: nil, selected: true}} =
             plan([time(lena)], [], [lena])
  end

  test "a member who signed up and didn't arrive is marked absent, a no-show" do
    sam = member(3, "Sam")

    assert %{"Sam" => %{action: :absent, selected: true, notes: []} = change} =
             plan([], [row(sam, "attending")], [sam])

    assert SendAttendanceToD4H.no_show?(change)
  end

  test "an invite nobody replied to is left alone" do
    jo = member(4, "Jo")
    assert plan([], [row(jo, "requested")], [jo]) == %{}
  end

  test "an absent row with no scan is left alone" do
    alex = member(5, "Alex")
    assert plan([], [row(alex, "absent")], [alex]) == %{}
  end

  test "attending with the same times already is no change" do
    mei = member(1, "Mei")

    assert %{"Mei" => %{action: :unchanged, selected: false}} =
             plan([time(mei)], [row(mei, "attending")], [mei])
  end

  test "times that need fixing can't be sent" do
    mei = member(1, "Mei")

    assert %{"Mei" => %{action: :blocked} = change} =
             plan([time(mei, [:left_before_arriving])], [row(mei, "requested")], [mei])

    refute SendAttendanceToD4H.sendable?(change)
  end

  test "a D4H row for someone not on the team is skipped" do
    stranger = member(9, "Stranger")
    assert plan([], [row(stranger, "attending")], []) == %{}
  end

  test "a member with two D4H rows gets one change, on the first row" do
    mei = member(1, "Mei")
    rows = [row(mei, "requested"), row(mei, "requested", d4h_attendance_id: 9999)]

    assert [%{action: :update, d4h_attendance_id: 5001}] =
             SendAttendanceToD4H.plan([time(mei)], rows, [mei])
  end

  test "refuses an activity deleted in D4H before reading D4H" do
    team = %Team{id: 1, d4h_access_key: "key"}
    activity = %Activity{team_id: 1, deleted_at: ~U[2026-10-05 06:00:00Z]}

    assert SendAttendanceToD4H.preview(team, activity) == {:error, :deleted}
    assert SendAttendanceToD4H.call(team, activity, %User{}, [], @start) == {:error, :deleted}
  end
end
