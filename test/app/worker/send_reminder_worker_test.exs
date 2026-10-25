defmodule App.Worker.SendReminderWorkerTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Reminder
  alias App.Operation.SendReminders
  alias App.Worker.SendReminderWorker

  setup do
    %{user: user, team: team} = user_with_team_fixture()
    starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)
    activity = activity_fixture(team, %{started_at: starts})
    member = member_fixture(team, %{name: "Cameron Ruiz", email: "cameron@example.com"})

    reminder =
      Repo.insert!(%Reminder{
        team_id: team.id,
        activity_id: activity.id,
        member_id: member.id,
        sent_by_user_id: user.id,
        sent_at: DateTime.utc_now(),
        round: 1,
        status: :queued
      })

    %{team: team, activity: activity, reminder: reminder}
  end

  defp perform(reminder, attempt \\ 1) do
    SendReminderWorker.perform(%Oban.Job{
      args: %{"reminder_id" => reminder.id},
      attempt: attempt,
      max_attempts: 5
    })
  end

  test "sends a queued reminder once, and tells its page", %{team: team} = ctx do
    Phoenix.PubSub.subscribe(App.PubSub, SendReminders.topic(team))

    assert perform(ctx.reminder) == :ok
    assert_received {:email, %{to: [{"Cameron Ruiz", "cameron@example.com"}]}}
    assert Repo.reload!(ctx.reminder).status == :sent
    assert_received {:reminder_done, activity_id} when activity_id == ctx.activity.id

    assert {:cancel, _reason} = perform(ctx.reminder)
    refute_received {:email, _}
  end

  test "a refusal is tried again, and the last one marks it failed", ctx do
    refusing_mailer_fixture()

    assert {:error, _reason} = perform(ctx.reminder, 1)
    assert Repo.reload!(ctx.reminder).status == :queued

    assert {:error, _reason} = perform(ctx.reminder, 5)
    assert %Reminder{status: :failed, error: error} = Repo.reload!(ctx.reminder)
    assert error =~ "500"
  end

  test "once the activity has started it isn't sent, and shows as failed", ctx do
    ctx.activity
    |> Ecto.Changeset.change(
      started_at: DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:cancel, _reason} = perform(ctx.reminder)
    refute_received {:email, _}

    assert %Reminder{status: :failed, error: "The activity started before it went."} =
             Repo.reload!(ctx.reminder)
  end

  test "retries over about an hour" do
    assert Enum.map(1..4, &SendReminderWorker.backoff(%Oban.Job{attempt: &1})) ==
             [60, 300, 900, 1800]
  end
end
