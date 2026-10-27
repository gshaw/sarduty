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

  defp reminder(member, sent_at, status \\ :sent),
    do: %Reminder{member_id: member.id, sent_at: sent_at, status: status}

  defp now, do: DateTime.utc_now()

  defp names(plan), do: Enum.map(plan.send, & &1.member.name)
  defp left_out(plan), do: Enum.map(plan.left_out, fn {m, reason} -> {m.name, reason} end)

  describe "plan/3" do
    test "each member with no reply can get one; the rest are named with why" do
      rows = [
        row(member(1, "Cameron Ruiz")),
        row(member(2, "Dana Clark", %{invitation_reminders: false})),
        row(member(3, "Eli Haddad", %{email: nil})),
        row(member(4, "Avery Chen"), "attending"),
        row(member(5, "Quinn Laval"), "absent")
      ]

      plan = SendReminders.plan(rows, [], MapSet.new())

      assert names(plan) == ["Cameron Ruiz"]
      assert left_out(plan) == [{"Dana Clark", :reminders_off}, {"Eli Haddad", :no_email}]

      assert Enum.map(plan.replied, &{&1.member.name, &1.status}) ==
               [{"Avery Chen", "attending"}, {"Quinn Laval", "absent"}]
    end

    test "a retiring member gets none, whatever their email (#514)" do
      rows = [row(member(1, "Cameron Ruiz")), row(member(2, "Avery Chen", %{email: nil}))]
      plan = SendReminders.plan(rows, [], MapSet.new([1, 2]))

      assert names(plan) == []
      assert left_out(plan) == [{"Avery Chen", :retiring}, {"Cameron Ruiz", :retiring}]
    end

    test "a member with a second row that has a reply has replied (#519)" do
      cameron = member(1, "Cameron Ruiz")
      rows = [row(cameron), row(cameron, "attending"), row(member(5, "Wren Adams"))]
      plan = SendReminders.plan(rows, [], MapSet.new())

      assert names(plan) == ["Wren Adams"]
      assert [%{member: %{name: "Cameron Ruiz"}, status: "attending"}] = plan.replied
    end

    test "emailed before has no limit, and lists each email that didn't fail, oldest first" do
      cameron = member(1, "Cameron Ruiz")
      first = DateTime.add(@now, -3, :day)
      second = DateTime.add(@now, -1, :hour)

      reminders = [
        reminder(cameron, second),
        reminder(cameron, DateTime.add(@now, -2, :day), :failed),
        reminder(cameron, first)
      ]

      assert %{send: [%{emailed: [%{sent_at: ^first}, %{sent_at: ^second}]}]} =
               SendReminders.plan([row(cameron)], reminders, MapSet.new())
    end

    test "a member who turned reminders off after an email gets no more" do
      dana = member(2, "Dana Clark", %{invitation_reminders: false})

      plan =
        SendReminders.plan([row(dana)], [reminder(dana, ~U[2026-10-20 18:00:00Z])], MapSet.new())

      assert plan.send == []
      assert left_out(plan) == [{"Dana Clark", :reminders_off}]
    end
  end

  describe "call/6" do
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
      assert {:ok, [%Reminder{status: :queued} = reminder]} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, [ctx.cameron.id], nil, now())

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
        refute email.html_body =~ "<br>"
        assert email.html_body =~ "I'll be there"
      end)

      # A team admin can send another whenever they choose.
      assert {:ok, [_again]} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, [ctx.cameron.id], nil, now())

      assert_email_sent(to: [{"Cameron Ruiz", "cameron@example.com"}])
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
                 nil,
                 now()
               )

      assert reminder.member_id == frankie.id
      assert_email_sent(to: [{"Frankie Moore", "frankie@example.com"}])
      refute_email_sent()
    end

    test "one send is one batch", ctx do
      frankie = member_fixture(ctx.team, %{name: "Frankie Moore", email: "frankie@example.com"})
      attendance_fixture(ctx.activity, frankie, %{status: "requested"})

      assert {:ok, reminders} =
               SendReminders.call(
                 ctx.team,
                 ctx.activity,
                 ctx.user,
                 [ctx.cameron.id, frankie.id],
                 nil,
                 now()
               )

      assert reminders |> Enum.map(& &1.member_id) |> Enum.sort() ==
               Enum.sort([ctx.cameron.id, frankie.id])

      assert reminders |> Enum.map(& &1.sent_at) |> Enum.uniq() |> length() == 1
    end

    test "carries the team admin's message, escaped, with its line breaks", ctx do
      message = "  Bring your rope kit.\r\nPark by the <hall> & the gate.\n"

      assert {:ok, [reminder]} =
               SendReminders.call(
                 ctx.team,
                 ctx.activity,
                 ctx.user,
                 [ctx.cameron.id],
                 message,
                 now()
               )

      assert Repo.reload!(reminder).message ==
               "Bring your rope kit.\nPark by the <hall> & the gate."

      assert_email_sent(fn email ->
        assert email.text_body =~ "Bring your rope kit.\nPark by the <hall> & the gate."

        assert email.html_body =~
                 "Bring your rope kit.<br>Park by the &lt;hall&gt; &amp; the gate."
      end)
    end

    test "a blank message is none", ctx do
      assert {:ok, [reminder]} =
               SendReminders.call(
                 ctx.team,
                 ctx.activity,
                 ctx.user,
                 [ctx.cameron.id],
                 " \n ",
                 now()
               )

      assert Repo.reload!(reminder).message == nil
    end

    test "a message over 300 characters sends nothing", ctx do
      long = String.duplicate("a", 301)

      assert {:error, :message_too_long} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, [ctx.cameron.id], long, now())

      assert SendReminders.error_text(:message_too_long) ==
               "Message must be 300 characters or fewer."

      refute_email_sent()

      assert {:ok, [_]} =
               SendReminders.call(
                 ctx.team,
                 ctx.activity,
                 ctx.user,
                 [ctx.cameron.id],
                 String.duplicate("é", 300),
                 now()
               )
    end

    test "nobody picked sends nothing", ctx do
      assert {:error, :none_selected} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, [], nil, now())

      refute_email_sent()
    end

    test "nothing goes once the activity has started", ctx do
      started = DateTime.add(ctx.activity.started_at, 1, :hour)

      assert {:error, :started} =
               SendReminders.call(
                 ctx.team,
                 ctx.activity,
                 ctx.user,
                 [ctx.cameron.id],
                 nil,
                 started
               )

      refute_email_sent()
    end
  end
end
