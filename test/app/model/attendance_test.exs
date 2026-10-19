defmodule App.Model.AttendanceTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Attendance

  @now ~U[2026-06-15 12:00:00Z]

  describe "attended/2 and signed_up/2" do
    test "a row is attended once it starts, and a sign-up before then (#364)" do
      team = team_fixture()
      member = member_fixture(team)
      past = activity_fixture(team, %{started_at: DateTime.add(@now, -1, :day)})
      coming = activity_fixture(team, %{started_at: DateTime.add(@now, 1, :day)})
      deleted = activity_fixture(team, %{started_at: past.started_at, deleted_at: @now})
      attended = attendance_fixture(past, member, %{started_at: past.started_at})
      starts_now = attendance_fixture(past, member, %{started_at: @now})
      signed_up = attendance_fixture(coming, member, %{started_at: coming.started_at})
      attendance_fixture(deleted, member, %{started_at: past.started_at})
      attendance_fixture(past, member, %{started_at: past.started_at, status: "absent"})

      assert ids(Attendance.attended(@now)) == Enum.sort([attended.id, starts_now.id])
      assert ids(Attendance.signed_up(@now)) == [signed_up.id]
    end

    defp ids(query), do: query |> select([r], r.id) |> Repo.all() |> Enum.sort()
  end

  # What attended means lives in Attendance.attended/2. A query that filters on
  # "attending" itself counts sign-ups for coming activities as attended (#364), and the
  # review of #381 found four such copies the fix had missed. These files use the
  # status for something else.
  @status_users %{
    "lib/app/model/attendance.ex" => "defines attended/2 and signed_up/2",
    "lib/app/model/activity.ex" => "an activity's rows, sign-ups included",
    "lib/web/live/activity_live.ex" => "one activity's list, sign-ups included",
    "lib/app/operation/send_attendance_to_d4h.ex" => "compares door scans to D4H rows",
    "lib/app/operation/build_mileage_report.ex" => "one activity's attendees",
    "lib/app/view_data/change_history.ex" => "a label",
    "lib/web/live/proposed_change_live.ex" => "a label",
    "lib/web/live/activity_take_attendance_live.ex" => "a label",
    "lib/web/live/activity_attendance_live.ex" => "one activity's rows, sign-ups included",
    "lib/web/components/attendance_table.ex" => "a label"
  }

  test "only Attendance says what attended means" do
    users =
      for path <- Path.wildcard("lib/**/*.{ex,exs,heex}"),
          not String.starts_with?(path, "lib/app/adapter/"),
          not Map.has_key?(@status_users, path),
          File.read!(path) =~ ~s("attending"),
          do: path

    assert users == [],
           "Use Attendance.attended/2 or signed_up/2, not \"attending\", in: #{inspect(users)}"
  end
end
