defmodule App.Operation.SendActivityUpdateTest do
  use App.DataCase, async: true

  import App.DataFixtures
  import Swoosh.TestAssertions

  alias App.Mailer.ActivityMailer
  alias App.Model.ActivityUpdate
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Operation.SendActivityUpdate

  @now ~U[2026-10-26 18:02:00Z]

  defp member(id, name, attrs \\ %{}),
    do:
      struct(
        %Member{id: id, name: name, email: "m#{id}@example.com", invitation_reminders: true},
        attrs
      )

  defp row(member, status), do: %Attendance{member_id: member.id, member: member, status: status}

  defp now, do: DateTime.utc_now()

  describe "plan/1" do
    test "a group per reply, in the rows' order, and who has no email" do
      rows = [
        row(member(1, "Avery Chen"), "attending"),
        row(member(2, "Quinn Laval"), "absent"),
        row(member(3, "Cameron Ruiz"), "requested"),
        row(member(4, "Eli Haddad", %{email: nil}), "requested")
      ]

      plan = SendActivityUpdate.plan(rows)

      assert Enum.map(plan.groups, fn {status, rows} ->
               {status, Enum.map(rows, & &1.member.name)}
             end) ==
               [
                 {"attending", ["Avery Chen"]},
                 {"absent", ["Quinn Laval"]},
                 {"requested", ["Cameron Ruiz"]}
               ]

      assert Enum.map(plan.no_email, & &1.name) == ["Eli Haddad"]
    end
  end

  test "update_ending/2: buttons for no reply unless reminders are off, else where they stand" do
    on = member(1, "On")
    off = member(2, "Off", %{invitation_reminders: false})

    assert ActivityMailer.update_ending("requested", on) == :ask
    assert ActivityMailer.update_ending("requested", off) == :open
    assert ActivityMailer.update_ending("attending", off) == :signed_up
    assert ActivityMailer.update_ending("absent", on) == :cant_make_it
  end

  test "sent_before/1: a batch per send, newest first, with its failures" do
    earlier = DateTime.add(@now, -1, :day)

    updates = [
      %ActivityUpdate{sent_at: earlier, message: "First", status: :sent},
      %ActivityUpdate{sent_at: @now, message: "Second", status: :sent},
      %ActivityUpdate{sent_at: @now, message: "Second", status: :failed},
      %ActivityUpdate{sent_at: @now, message: "Sorry", status: :sent, kind: :removal}
    ]

    assert [
             %{sent_at: @now, message: "Second", members: 2, failed: 1},
             %{sent_at: ^earlier, message: "First", members: 1, failed: 0}
           ] = SendActivityUpdate.sent_before(updates)
  end

  describe "call/6" do
    setup do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{name: "Coast Range SAR"}})
      admin = Repo.get_by!(Member, team_id: team.id, email: user.email)
      admin |> Ecto.Changeset.change(name: "Alex Chen") |> Repo.update!()
      starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)
      activity = activity_fixture(team, %{title: "Training night", started_at: starts})

      add = fn name, status, attrs ->
        email = name |> String.downcase() |> String.replace(" ", ".")

        m =
          team
          |> member_fixture(%{name: name, email: "#{email}@example.com"})
          |> Ecto.Changeset.change(attrs)
          |> Repo.update!()

        attendance_fixture(activity, m, %{status: status})
        m
      end

      %{
        user: user,
        team: team,
        activity: activity,
        avery: add.("Avery Chen", "attending", %{}),
        quinn: add.("Quinn Laval", "absent", %{}),
        cameron: add.("Cameron Ruiz", "requested", %{}),
        dana: add.("Dana Clark", "requested", %{invitation_reminders: false})
      }
    end

    defp send_update(ctx, ids, message \\ "Meet at the pullout, not the hall."),
      do: SendActivityUpdate.call(ctx.team, ctx.activity, ctx.user, ids, message, now())

    test "each email ends with where its member stands", ctx do
      ids = [ctx.avery.id, ctx.quinn.id, ctx.cameron.id, ctx.dana.id]
      assert {:ok, updates} = send_update(ctx, ids)
      assert length(updates) == 4
      assert Enum.all?(updates, &(Repo.reload!(&1).status == :sent))

      emails =
        for _ <- 1..4, into: %{} do
          assert_received {:email, %{to: [{name, _}]} = email}
          {name, email}
        end

      avery = emails["Avery Chen"]
      assert avery.subject == "Update: Training night"
      assert avery.reply_to == {"Alex Chen", ctx.user.email}
      assert avery.headers == %{}
      assert avery.text_body =~ "Meet at the pullout, not the hall."
      assert avery.text_body =~ ~r{You're signed up\.\n\nChange your reply:\n\S+\?reply=no}
      refute avery.html_body =~ "I'll be there"
      refute avery.html_body =~ "Turn off invitation reminders"

      assert emails["Quinn Laval"].text_body =~
               ~r{You said you can't make it\.\n\nChange your reply:\n\S+\?reply=yes}

      assert emails["Cameron Ruiz"].html_body =~ "I'll be there"
      assert emails["Cameron Ruiz"].text_body =~ "Will you be there?"

      dana = emails["Dana Clark"]
      refute dana.html_body =~ "I'll be there"
      refute dana.html_body =~ "Change your reply"
      assert dana.html_body =~ "Open activity"
    end

    test "a member who left the activity before it went gets none", ctx do
      update =
        Repo.insert!(%ActivityUpdate{
          team_id: ctx.team.id,
          activity_id: ctx.activity.id,
          member_id: ctx.avery.id,
          sent_by_user_id: ctx.user.id,
          message: "Hi",
          sent_at: now(),
          status: :queued
        })

      Repo.delete_all(Attendance)

      assert {:cancel, _} = SendActivityUpdate.deliver(update.id, false, now())
      assert Repo.reload!(update).status == :failed
      refute_email_sent()
    end

    # Remove members (#704) deletes the copy's rows before the job runs.
    test "a removal goes after the start, unless the member is back on", ctx do
      removal = fn ->
        Repo.insert!(%ActivityUpdate{
          team_id: ctx.team.id,
          activity_id: ctx.activity.id,
          member_id: ctx.avery.id,
          sent_by_user_id: ctx.user.id,
          message: "Sorry",
          sent_at: now(),
          status: :queued,
          kind: :removal
        })
      end

      Repo.delete_all(Attendance)
      later = DateTime.add(ctx.activity.started_at, 1, :hour)
      update = removal.()
      assert SendActivityUpdate.deliver(update.id, false, later) == :ok
      assert Repo.reload!(update).status == :sent
      assert_received {:email, %{subject: "You're no longer on Training night"} = email}
      assert email.html_body =~ "You're no longer on this activity."
      refute email.html_body =~ "Open activity"

      attendance_fixture(ctx.activity, ctx.avery, %{status: "requested"})
      update = removal.()
      assert {:cancel, _} = SendActivityUpdate.deliver(update.id, false, now())
      assert Repo.reload!(update).status == :failed
      refute_email_sent()
    end

    test "stores the message with each row", ctx do
      assert {:ok, [update]} =
               send_update(ctx, [ctx.avery.id], "  Bring a headlamp.\r\nPark by the gate. ")

      assert Repo.reload!(update).message == "Bring a headlamp.\nPark by the gate."
    end

    test "only to the members picked who are on the activity", ctx do
      other = member_fixture(ctx.team, %{name: "Riley Stone"})
      assert {:ok, [update]} = send_update(ctx, [ctx.quinn.id, other.id])
      assert update.member_id == ctx.quinn.id
      assert_email_sent(to: [{"Quinn Laval", "quinn.laval@example.com"}])
      refute_email_sent()
    end

    test "refuses no message, a long one, nobody, and a started activity", ctx do
      assert send_update(ctx, [ctx.avery.id], " \n ") == {:error, :no_message}

      assert send_update(ctx, [ctx.avery.id], String.duplicate("a", 301)) ==
               {:error, :message_too_long}

      assert send_update(ctx, []) == {:error, :none_selected}

      started = DateTime.add(ctx.activity.started_at, 1, :hour)

      assert SendActivityUpdate.call(
               ctx.team,
               ctx.activity,
               ctx.user,
               [ctx.avery.id],
               "Hi",
               started
             ) ==
               {:error, :started}

      assert SendActivityUpdate.error_text(:no_message) == "Enter a message."
      refute_email_sent()
    end
  end
end
