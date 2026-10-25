defmodule App.Operation.SendReminders do
  @moduledoc """
  A team admin emails reminders to members who haven't replied to an activity (#444),
  at once, before it starts. Round 1 goes to members with no reply and no reminder yet.
  Round 2, Ask again, goes to those still with no reply 24 hours or more after their
  round 1. Never a third: after round 2, only newly invited members get one. A member
  with no email in D4H, or with invitation reminders off, is skipped and named.

  plan/4 says who gets one, pure. call/5 records a queued row per reminder with its
  job, in one transaction, so two team admins sending at once can't send twice.
  App.Worker.SendReminderWorker then sends each with deliver/3, retrying a refusal.
  """
  import Ecto.Query

  alias App.Accounts.User
  alias App.Mailer.ReminderMailer
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Reminder
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.SendReminderWorker

  @wait 24 * 60 * 60

  @doc """
  Who round `round` goes to, from the activity's rows of any status (with their
  members) and its `reminders` so far, as `%{send: [member], skipped: [{member,
  :no_email | :reminders_off}]}`, each by name.
  """
  def plan(rows, reminders, round, %DateTime{} = now) when round in [1, 2] do
    by_member = Enum.group_by(reminders, & &1.member_id)

    {send, skipped} =
      rows
      |> no_reply_members()
      |> Enum.filter(&due?(Map.get(by_member, &1.id, []), round, now))
      |> Enum.split_with(&reachable?/1)

    %{send: send, skipped: Enum.map(skipped, &{&1, skip_reason(&1)})}
  end

  # Each member with no reply once, by name. A member with a second row that has a
  # reply has replied (#519).
  defp no_reply_members(rows) do
    rows
    |> Attendance.one_per_member()
    |> Enum.filter(&(&1.status == "requested"))
    |> Enum.map(& &1.member)
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp due?(reminders, 1, _now), do: not Enum.any?(reminders, &(&1.round == 1))

  defp due?(reminders, 2, now) do
    case Enum.find(reminders, &(&1.round == 1)) do
      nil ->
        false

      first ->
        not Enum.any?(reminders, &(&1.round == 2)) and DateTime.diff(now, first.sent_at) >= @wait
    end
  end

  defp reachable?(%Member{} = member),
    do: member.email not in [nil, ""] and member.invitation_reminders

  defp skip_reason(%Member{email: email}) when email in [nil, ""], do: :no_email
  defp skip_reason(%Member{}), do: :reminders_off

  @doc """
  Queues round `round` from `user`. `{:ok, reminders}`, each queued, or `{:error,
  text}` once the activity has started or is deleted.
  """
  def call(%Team{} = team, %Activity{team_id: team_id} = activity, %User{} = user, round, now)
      when team_id == team.id and round in [1, 2] do
    cond do
      activity.deleted_at ->
        {:error, "This activity is deleted."}

      not DateTime.before?(now, activity.started_at) ->
        {:error, "Reminders closed when the activity started."}

      true ->
        %{send: members} =
          plan(invited_rows(activity), Reminder.for_activity(activity), round, now)

        {:ok, Enum.flat_map(members, &queue(activity, &1, user, round, now))}
    end
  end

  # The activity's rows, scoped through the team; plan/4 keeps those with no reply.
  defp invited_rows(activity) do
    Attendance
    |> join(:inner, [r], m in assoc(r, :member))
    |> where([r, m], r.activity_id == ^activity.id and m.team_id == ^activity.team_id)
    |> preload([r, m], member: m)
    |> Repo.all()
  end

  # The row and its job commit together, or neither does.
  defp queue(activity, member, user, round, now) do
    {:ok, queued} =
      Repo.transaction(fn ->
        case activity |> row(member, user, round, now) |> Reminder.insert() do
          nil ->
            []

          reminder ->
            SendReminderWorker.enqueue(reminder)
            [reminder]
        end
      end)

    queued
  end

  defp row(activity, member, user, round, now) do
    %Reminder{
      team_id: activity.team_id,
      activity_id: activity.id,
      member_id: member.id,
      sent_by_user_id: user.id,
      sent_at: now,
      round: round,
      status: :queued
    }
  end

  @doc """
  Emails one queued reminder and marks it sent, for its job. A refusal is `{:error,
  reason}`, so the job tries again; on the `last?` attempt the reminder is marked failed
  first. One no longer queued is `{:cancel, reason}`, and so is one whose activity
  started or was deleted before it went, which is marked failed. The activity's page
  hears through `topic/1` once a reminder is sent or failed.
  """
  def deliver(reminder_id, last?, now) do
    case Reminder.get_queued(reminder_id) do
      nil -> {:cancel, "no queued reminder"}
      reminder -> deliver_queued(reminder, last?, now)
    end
  end

  defp deliver_queued(%Reminder{activity: activity} = reminder, last?, now) do
    if activity.deleted_at || not DateTime.before?(now, activity.started_at) do
      reminder |> Reminder.fail!("The activity started before it went.") |> broadcast()
      {:cancel, "the activity started"}
    else
      send_email(reminder, last?, now)
    end
  end

  defp send_email(%Reminder{team: team} = reminder, last?, now) do
    sender = sender(team, reminder.sent_by_user, now)

    case ReminderMailer.deliver(reminder.member, reminder.activity, team, sender) do
      {:ok, _sent} ->
        reminder |> Reminder.sent!() |> broadcast()
        :ok

      {:error, error} ->
        if last?, do: reminder |> Reminder.fail!(inspect(error)) |> broadcast()
        {:error, error}
    end
  end

  @doc "The topic a team's reminder changes go out on, as `{:reminder_done, activity_id}`."
  def topic(%Team{id: team_id}), do: "reminders:#{team_id}"

  defp broadcast(%Reminder{} = reminder) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      topic(%Team{id: reminder.team_id}),
      {:reminder_done, reminder.activity_id}
    )
  end

  @doc """
  Who a reminder is from, `%{name:, email:}`: the team admin's own member name on the
  team, when D4H has one, for the email's reply-to and its last line.
  """
  def sender(%Team{} = team, %User{} = user, now) do
    member = Member.find_by_email(team, user.email, now)
    %{name: member && member.name, email: user.email}
  end
end
