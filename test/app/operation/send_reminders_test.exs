defmodule App.Operation.SendRemindersTest do
  use App.DataCase, async: true

  import App.DataFixtures
  import Swoosh.TestAssertions

  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Reminder
  alias App.Operation.SendReminders

  @now ~U[2026-10-26 18:02:00Z]

  defp member(id, name, attrs \\ %{}),
    do:
      struct(
        %Member{id: id, name: name, email: "m#{id}@example.com", invitation_reminders: true},
        attrs
      )

  defp row(member, status \\ "requested"),
    do: %Attendance{member_id: member.id, member: member, status: status}

  defp reminder(member, round, sent_at),
    do: %Reminder{member_id: member.id, round: round, sent_at: sent_at, status: :sent}

  defp names(members), do: Enum.map(members, & &1.name)

  describe "plan/4" do
    test "round 1 goes to members with no reply, and names who it skips and why" do
      dana = member(2, "Dana Clark", %{invitation_reminders: false})
      eli = member(3, "Eli Haddad", %{email: nil})

      rows = [
        row(member(1, "Cameron Ruiz")),
        row(dana),
        row(eli),
        row(member(4, "Avery Chen"), "attending")
      ]

      plan = SendReminders.plan(rows, [], 1, @now)

      assert names(plan.send) == ["Cameron Ruiz"]

      assert [{%{name: "Dana Clark"}, :reminders_off}, {%{name: "Eli Haddad"}, :no_email}] =
               plan.skipped
    end

    test "one round 1 per member: a later send goes only to the newly invited" do
      cameron = member(1, "Cameron Ruiz")
      rows = [row(cameron), row(member(5, "Wren Adams"))]

      plan = SendReminders.plan(rows, [reminder(cameron, 1, @now)], 1, @now)

      assert names(plan.send) == ["Wren Adams"]
    end

    test "round 2 goes 24 hours after round 1, to members still with no reply, once" do
      cameron = member(1, "Cameron Ruiz")
      frankie = member(2, "Frankie Moore")
      rows = [row(cameron), row(frankie), row(member(3, "Quinn Laval"), "absent")]
      day_ago = DateTime.add(@now, -24, :hour)

      first = [
        reminder(cameron, 1, day_ago),
        reminder(frankie, 1, DateTime.add(@now, -23, :hour))
      ]

      assert names(SendReminders.plan(rows, first, 2, @now).send) == ["Cameron Ruiz"]
      assert SendReminders.plan(rows, [], 2, @now).send == []

      both = [reminder(cameron, 2, @now) | first]
      assert SendReminders.plan(rows, both, 2, DateTime.add(@now, 2, :day)).send == [frankie]
    end
  end

  describe "call/5" do
    setup do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{name: "Coast Range SAR"}})
      admin = Repo.get_by!(Member, team_id: team.id, email: user.email)
      admin = admin |> Ecto.Changeset.change(name: "Alex Chen") |> Repo.update!()
      starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)
      activity = activity_fixture(team, %{title: "Training night", started_at: starts})
      cameron = member_fixture(team, %{name: "Cameron Ruiz", email: "cameron@example.com"})
      attendance_fixture(activity, cameron, %{status: "requested"})
      %{user: user, team: team, admin: admin, activity: activity, cameron: cameron}
    end

    test "emails each member at once, from the team, with replies to the team admin", ctx do
      assert {:ok, [%Reminder{status: :sent, round: 1}]} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, 1, DateTime.utc_now())

      assert_email_sent(fn email ->
        assert email.to == [{"Cameron Ruiz", "cameron@example.com"}]
        assert email.from == {"Coast Range SAR", "noreply@sarduty.com"}
        assert email.reply_to == {"Alex Chen", ctx.user.email}
        assert email.subject == "Will you be there? Training night"
        assert email.headers["List-Unsubscribe"] =~ ~r{^<http.*/reminders/.+>$}
        assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
        assert email.text_body =~ "/replies/"
        assert email.text_body =~ "Alex Chen, a team admin, sent this reminder."
        assert email.html_body =~ "I'll be there"
      end)

      # Sending again reaches nobody new.
      assert {:ok, []} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, 1, DateTime.utc_now())

      refute_email_sent()
    end

    test "nothing goes once the activity has started", ctx do
      started = DateTime.add(ctx.activity.started_at, 1, :hour)

      assert {:error, "Reminders closed when the activity started."} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, 1, started)

      refute_email_sent()
    end
  end
end
