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

  defp now, do: DateTime.utc_now()

  # Who gets which email, as {name, round}.
  defp emails(plan), do: Enum.map(plan.send, &{&1.member.name, &1.round})
  defp left_out(plan), do: Enum.map(plan.left_out, fn {m, reason} -> {m.name, reason} end)

  describe "plan/3" do
    test "a first email goes to each member with no reply; the rest are named with why" do
      rows = [
        row(member(1, "Cameron Ruiz")),
        row(member(2, "Dana Clark", %{invitation_reminders: false})),
        row(member(3, "Eli Haddad", %{email: nil})),
        row(member(4, "Avery Chen"), "attending"),
        row(member(5, "Quinn Laval"), "absent")
      ]

      plan = SendReminders.plan(rows, [], @now)

      assert emails(plan) == [{"Cameron Ruiz", 1}]
      assert left_out(plan) == [{"Dana Clark", :reminders_off}, {"Eli Haddad", :no_email}]

      assert Enum.map(plan.replied, &{&1.member.name, &1.status}) ==
               [{"Avery Chen", "attending"}, {"Quinn Laval", "absent"}]
    end

    test "a member with a second row that has a reply has replied (#519)" do
      cameron = member(1, "Cameron Ruiz")
      rows = [row(cameron), row(cameron, "attending"), row(member(5, "Wren Adams"))]
      plan = SendReminders.plan(rows, [], @now)

      assert emails(plan) == [{"Wren Adams", 1}]
      assert [%{member: %{name: "Cameron Ruiz"}, status: "attending"}] = plan.replied
    end

    test "one send mixes first and second emails, a day apart, at most 2 each" do
      cameron = member(1, "Cameron Ruiz")
      frankie = member(2, "Frankie Moore")
      jordan = member(3, "Jordan Lee")
      harper = member(4, "Harper Nguyen")
      day_ago = DateTime.add(@now, -24, :hour)
      rows = Enum.map([cameron, frankie, jordan, harper], &row/1)

      reminders = [
        reminder(cameron, 1, day_ago),
        reminder(frankie, 1, DateTime.add(@now, -23, :hour)),
        reminder(harper, 1, DateTime.add(@now, -3, :day)),
        reminder(harper, 2, day_ago)
      ]

      plan = SendReminders.plan(rows, reminders, @now)

      assert emails(plan) == [{"Cameron Ruiz", 2}, {"Jordan Lee", 1}]
      assert [%{first: %Reminder{sent_at: ^day_ago}}, %{first: nil}] = plan.send
      assert left_out(plan) == [{"Frankie Moore", :too_soon}, {"Harper Nguyen", :had_both}]
    end

    test "a member who turned reminders off after their first gets no second" do
      dana = member(2, "Dana Clark", %{invitation_reminders: false})
      plan = SendReminders.plan([row(dana)], [reminder(dana, 1, ~U[2026-10-20 18:00:00Z])], @now)

      assert plan.send == []
      assert left_out(plan) == [{"Dana Clark", :reminders_off}]
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
      assert {:ok, [%Reminder{status: :queued, round: 1} = reminder]} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, [ctx.cameron.id], now())

      # Its job ran as it was queued, since Oban runs inline in tests.
      assert Repo.reload!(reminder).status == :sent

      assert_email_sent(fn email ->
        assert email.to == [{"Cameron Ruiz", "cameron@example.com"}]
        assert email.from == {"Coast Range SAR", "noreply@sarduty.com"}
        assert email.reply_to == {"Alex Chen", ctx.user.email}
        assert email.subject == "Will you be there? Training night"
        assert email.headers["List-Unsubscribe"] =~ ~r{^<http.*/reminders/.+>$}
        assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
        assert email.text_body =~ ~r{/replies/\S+\?reply=yes}
        assert email.text_body =~ ~r{/replies/\S+\?reply=no}
        assert email.html_body =~ "?reply=yes"
        assert email.html_body =~ "?reply=no"
        assert email.text_body =~ "Alex Chen, a team admin, sent this email."
        assert email.html_body =~ "I'll be there"
      end)

      # Sending again reaches nobody: the second waits a day.
      assert {:ok, []} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, [ctx.cameron.id], now())

      refute_email_sent()
    end

    test "only to the members picked, and only those the plan has", ctx do
      frankie = member_fixture(ctx.team, %{name: "Frankie Moore", email: "frankie@example.com"})
      attendance_fixture(ctx.activity, frankie, %{status: "requested"})
      other_team_member = member_fixture(team_fixture(), %{name: "Riley Stone"})

      assert {:ok, [%Reminder{} = reminder]} =
               SendReminders.call(
                 ctx.team,
                 ctx.activity,
                 ctx.user,
                 [frankie.id, other_team_member.id, ctx.admin.id],
                 now()
               )

      assert reminder.member_id == frankie.id
      assert_email_sent(to: [{"Frankie Moore", "frankie@example.com"}])
      refute_email_sent()
    end

    test "a second email goes with a first in one send, as one batch", ctx do
      frankie = member_fixture(ctx.team, %{name: "Frankie Moore", email: "frankie@example.com"})
      attendance_fixture(ctx.activity, frankie, %{status: "requested"})
      day_ago = DateTime.add(now(), -25, :hour)

      Repo.insert!(%Reminder{
        team_id: ctx.team.id,
        activity_id: ctx.activity.id,
        member_id: ctx.cameron.id,
        sent_at: day_ago,
        round: 1,
        status: :sent
      })

      assert {:ok, reminders} =
               SendReminders.call(
                 ctx.team,
                 ctx.activity,
                 ctx.user,
                 [ctx.cameron.id, frankie.id],
                 now()
               )

      assert reminders |> Enum.map(&{&1.member_id, &1.round}) |> Enum.sort() ==
               Enum.sort([{ctx.cameron.id, 2}, {frankie.id, 1}])

      assert reminders |> Enum.map(& &1.sent_at) |> Enum.uniq() |> length() == 1
    end

    test "nobody picked sends nothing", ctx do
      assert {:error, :none_selected} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, [], now())

      refute_email_sent()
    end

    test "nothing goes once the activity has started", ctx do
      started = DateTime.add(ctx.activity.started_at, 1, :hour)

      assert {:error, :started} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, [ctx.cameron.id], started)

      refute_email_sent()
    end
  end
end
