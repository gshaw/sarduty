defmodule App.ViewData.ActivityRemindersTest do
  use ExUnit.Case, async: true

  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Reminder
  alias App.ViewData.ActivityReminders

  @now ~U[2026-10-27 18:02:00Z]
  @first ~U[2026-10-26 01:02:00Z]

  defp member(id),
    do: %Member{id: id, name: "M#{id}", email: "m#{id}@example.com", invitation_reminders: true}

  defp row(id, status), do: %Attendance{member_id: id, member: member(id), status: status}

  defp reminder(id, round, sent_at, status \\ :sent),
    do: %Reminder{member_id: id, round: round, sent_at: sent_at, status: status}

  test "the last batch counts its members who replied since" do
    reminders = [
      reminder(1, 1, @first),
      reminder(2, 1, @first),
      reminder(3, 1, @first, :failed)
    ]

    rows = [row(1, "attending"), row(2, "requested"), row(3, "requested")]

    assert %{sent: 2, failed: 1, replied_since: 1, sent_at: @first} =
             ActivityReminders.last_batch(reminders, rows)

    assert ActivityReminders.last_batch([], rows) == nil
  end

  test "a member's latest reminder is their last round" do
    reminders = [reminder(1, 2, @now), reminder(1, 1, @first)]
    assert %{1 => %Reminder{round: 2}} = ActivityReminders.latest(reminders)
  end

  test "round 1 comes before Ask again" do
    rows = [row(1, "requested"), row(2, "requested")]

    assert {1, %{send: [%{id: 2}]}} =
             ActivityReminders.next_round(rows, [reminder(1, 1, @first)], @now)

    assert {2, %{send: [%{id: 1}, %{id: 2}]}} =
             ActivityReminders.next_round(
               rows,
               [reminder(1, 1, @first), reminder(2, 1, @first)],
               @now
             )

    done = for id <- [1, 2], round <- [1, 2], do: reminder(id, round, @first)
    assert ActivityReminders.next_round(rows, done, @now) == nil
  end
end
