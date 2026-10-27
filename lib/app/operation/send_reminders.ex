defmodule App.Operation.SendReminders do
  @moduledoc """
  A team admin emails reminders to members who haven't replied to an activity (#444),
  from Send reminders (#608), before it starts. Each send goes to the members they leave
  checked; the page shows when each was emailed before, and the team admin decides.
  Members who replied get none, and the page says why each other member gets none
  either.

  A send can carry a message, the team admin's own words at the top of the email, up to
  300 characters (#609).

  plan/2 says who can get one and why the rest can't, pure. call/6 records a queued row
  per reminder with its job, in one transaction. App.Worker.SendReminderWorker then
  sends each with deliver/3, retrying a refusal.
  """
  import Ecto.Query

  alias App.Accounts.User
  alias App.Mailer.ActivityMailer
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Reminder
  alias App.Model.Team
  alias App.Repo
  alias App.Validate.Message
  alias App.Worker.SendReminderWorker

  @doc """
  Who can get a reminder now, from the activity's rows of any status (with their
  members) and its `reminders` so far. Each list is by name:

    * `send`: `%{member:, emailed: [reminder]}`, with the member's reminders that
      didn't fail, oldest first.
    * `replied`: the rows of members who answered, so get none.
    * `left_out`: `{member, :no_email | :reminders_off}` for the others with no reply.
  """
  def plan(rows, reminders) do
    by_member = reminders |> Enum.reject(&(&1.status == :failed)) |> Enum.group_by(& &1.member_id)
    {no_reply, replied} = by_reply(rows)

    {send, left_out} =
      no_reply
      |> Enum.map(&email(&1.member, Map.get(by_member, &1.member_id, [])))
      |> Enum.split_with(&is_map/1)

    %{send: send, replied: replied, left_out: left_out}
  end

  # Each member once, by name, as {no reply, replied}. A member with a second row that
  # has a reply has replied (#519).
  defp by_reply(rows) do
    rows
    |> Attendance.one_per_member()
    |> Enum.sort_by(&String.downcase(&1.member.name))
    |> Enum.split_with(&(&1.status == "requested"))
  end

  defp email(%Member{email: email} = member, _emailed) when email in [nil, ""],
    do: {member, :no_email}

  defp email(%Member{invitation_reminders: false} = member, _emailed),
    do: {member, :reminders_off}

  defp email(member, emailed),
    do: %{member: member, emailed: Enum.sort_by(emailed, & &1.sent_at, DateTime)}

  @doc """
  Queues a reminder for each member in `member_ids` that plan/2 has, from `user`, with
  `message` (see App.Validate.Message). Ids the plan doesn't have are ignored. `{:ok, reminders}`,
  each queued, or `{:error, reason}`: `:none_selected`, `:message_too_long`,
  `:deleted`, or `:started`.
  """
  def call(
        %Team{} = team,
        %Activity{team_id: team_id} = activity,
        %User{} = user,
        member_ids,
        message,
        now
      )
      when team_id == team.id do
    ids = MapSet.new(member_ids)
    message = Message.normalize(message)

    cond do
      activity.deleted_at ->
        {:error, :deleted}

      not DateTime.before?(now, activity.started_at) ->
        {:error, :started}

      MapSet.size(ids) == 0 ->
        {:error, :none_selected}

      not Message.fits?(message) ->
        {:error, :message_too_long}

      true ->
        {:ok, queue_picked(activity, user, ids, message, now)}
    end
  end

  defp queue_picked(activity, user, ids, message, now) do
    %{send: emails} = plan(invited_rows(activity), Reminder.for_activity(activity))

    for email <- emails,
        MapSet.member?(ids, email.member.id),
        do: queue(activity, email.member, user, message, now)
  end

  @doc "What a call/6 error says."
  def error_text(:none_selected), do: "Select at least 1 member to email."

  def error_text(:message_too_long), do: Message.error_text()

  def error_text(:deleted), do: "This activity is deleted. Nothing can be sent to it."
  def error_text(:started), do: "Reminders closed when the activity started."

  # The activity's rows, scoped through the team.
  defp invited_rows(activity) do
    Attendance
    |> join(:inner, [r], m in assoc(r, :member))
    |> where([r, m], r.activity_id == ^activity.id and m.team_id == ^activity.team_id)
    |> preload([r, m], member: m)
    |> Repo.all()
  end

  # The row and its job commit together, or neither does.
  defp queue(activity, member, user, message, now) do
    {:ok, reminder} =
      Repo.transaction(fn ->
        reminder = activity |> row(member, user, message, now) |> Repo.insert!()
        SendReminderWorker.enqueue(reminder)
        reminder
      end)

    reminder
  end

  defp row(activity, member, user, message, now) do
    %Reminder{
      team_id: activity.team_id,
      activity_id: activity.id,
      member_id: member.id,
      sent_by_user_id: user.id,
      sent_at: now,
      status: :queued,
      message: message
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

    case ActivityMailer.deliver_reminder(
           reminder.member,
           reminder.activity,
           team,
           sender,
           reminder.message
         ) do
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
