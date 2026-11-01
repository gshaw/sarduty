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

  describe "one row per member per activity (#519)" do
    defp row(id, activity_id, member_id, status),
      do: %Attendance{id: id, activity_id: activity_id, member_id: member_id, status: status}

    test "the row with a reply wins, then the oldest, in the first row's order" do
      rows = [
        row(1, 10, 1, "requested"),
        row(2, 10, 2, "requested"),
        row(3, 10, 1, "attending"),
        row(4, 10, 3, "absent"),
        row(5, 10, 3, "attending"),
        row(6, 10, 2, "requested"),
        row(7, 10, 4, "requested"),
        row(8, 10, 4, "absent"),
        row(9, 11, 1, "requested")
      ]

      assert rows |> Attendance.one_per_member() |> Enum.map(& &1.id) == [3, 2, 5, 8, 9]
    end

    test "counts each member once, with every activity zeroed" do
      rows = [row(1, 10, 1, "requested"), row(2, 10, 1, "attending"), row(3, 10, 2, "absent")]

      assert Attendance.count_replies(rows, [10, 11]) == %{
               10 => %{attending: 1, absent: 1, requested: 0},
               11 => %{attending: 0, absent: 0, requested: 0}
             }
    end

    test "a reply changes the row the page shows" do
      team = team_fixture()
      member = member_fixture(team)
      activity = activity_fixture(team)
      attendance_fixture(activity, member, %{status: "requested"})
      shown = attendance_fixture(activity, member, %{status: "attending"})

      assert Attendance.invitation(activity, member).id == shown.id
      assert Attendance.invitations(member, [activity.id])[activity.id].id == shown.id

      assert Attendance.reply_counts(team, [activity.id]) == %{
               activity.id => %{attending: 1, absent: 0, requested: 0}
             }
    end
  end

  describe "replied_at/4, as the refresh sees a row change (#444)" do
    @starts ~U[2026-10-29 02:00:00Z]
    @changed ~U[2026-10-26 16:12:30.123456Z]
    @earlier ~U[2026-10-20 10:02:00Z]

    # The row was `old` (status, replied_at); D4H now has `status`, changed at `changed_at`.
    defp replied({old_status, old_replied_at}, status, changed_at \\ @changed) do
      %Attendance{status: old_status, replied_at: old_replied_at}
      |> Attendance.replied_at(status, changed_at, @starts)
    end

    test "a status D4H changed before the start is a reply then" do
      assert replied({"requested", nil}, "attending") == ~U[2026-10-26 16:12:30Z]
      assert replied({"requested", nil}, "absent") == ~U[2026-10-26 16:12:30Z]
      assert replied({"attending", @earlier}, "absent") == ~U[2026-10-26 16:12:30Z]
    end

    test "the same status keeps the time the member replied" do
      assert replied({"attending", @earlier}, "attending") == @earlier
      assert replied({"requested", nil}, "requested") == nil
    end

    test "back to requested is no reply" do
      assert replied({"attending", @earlier}, "requested") == nil
    end

    # The door marks walk-ins and no-shows once it starts; they never replied.
    test "a change after the start keeps what was there" do
      after_start = DateTime.add(@starts, 600)
      assert replied({"requested", nil}, "attending", after_start) == nil
      assert replied({"attending", @earlier}, "absent", after_start) == @earlier
    end

    # A team's first refresh copies every row; none of that is a reply.
    test "a new row has no reply time" do
      assert Attendance.replied_at(nil, "attending", @changed, @starts) == nil
    end
  end

  describe "invitation/2" do
    test "is the member's row on the activity, only on their team" do
      team = team_fixture()
      other_team = team_fixture()
      member = member_fixture(team)
      outsider = member_fixture(other_team)
      activity = activity_fixture(team)
      row = attendance_fixture(activity, member, %{status: "requested"})
      # A row that crosses teams is never someone's invitation.
      attendance_fixture(activity, outsider, %{status: "requested"})

      assert Attendance.invitation(activity, member).id == row.id
      assert Attendance.invitation(activity, outsider) == nil
      not_invited = activity_fixture(team)
      assert Attendance.invitation(not_invited, member) == nil
    end
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
    "lib/web/live/activity_attendance_live.ex" => "a label",
    "lib/app/operation/build_chore_event.ex" => "a D4H row's own status, to leave a row alone",
    "lib/web/components/reply.ex" => "a member's own reply, before the start",
    "lib/app/view_data/activity_members.ex" => "one activity's replies, sign-ups included",
    "lib/app/mailer/activity_mailer.ex" => "how an update ends, from a reply before the start",
    "lib/web/live/activity_send_update_live.ex" => "a label",
    "lib/app/operation/remove_members.ex" => "a signed up member's reply, before the start",
    "lib/web/live/activity_remove_members_live.ex" => "a table per reply, before the start",
    "lib/app/operation/refresh_d4h_data/upsert_attendances.ex" =>
      "a no-show's row changed to attending in D4H"
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
