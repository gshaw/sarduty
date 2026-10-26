defmodule App.Operation.SendReminders do
  @moduledoc """
  A team admin emails reminders to members who haven't replied to an activity (#444),
  from Email members (#608), before it starts. Each member gets at most 2: the first,
  then the second and last 24 hours or more after it. One send mixes them, member by
  member. Members who replied get none, and the page says why each other member gets
  none either.

  plan/3 says who gets which email and why the rest get none, pure. call/5 records a
  queued row per reminder with its job, in one transaction, so two team admins sending
  at once can't send twice. App.Worker.SendReminderWorker then sends each with
  deliver/3, retrying a refusal.
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
  Who gets which email now, from the activity's rows of any status (with their members)
  and its `reminders` so far. Each list is by name:

    * `send`: `%{member:, round: 1 | 2, first: nil | reminder}`, `first` being the
      member's first reminder for a second.
    * `replied`: the rows of members who answered, so get none.
    * `left_out`: `{member, reason}` for the others with no reply: `:had_both`,
      `:no_email`, `:reminders_off`, or `:too_soon`, a first less than 24 hours ago.
  """
  def plan(rows, reminders, %DateTime{} = now) do
    by_member = Enum.group_by(reminders, & &1.member_id)
    {no_reply, replied} = by_reply(rows)

    {send, left_out} =
      no_reply
      |> Enum.map(&email(&1.member, Map.get(by_member, &1.member_id, []), now))
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

  # A member's next email, or why they get none.
  defp email(member, reminders, now) do
    first = Enum.find(reminders, &(&1.round == 1))

    cond do
      Enum.any?(reminders, &(&1.round == 2)) -> {member, :had_both}
      member.email in [nil, ""] -> {member, :no_email}
      not member.invitation_reminders -> {member, :reminders_off}
      first == nil -> %{member: member, round: 1, first: nil}
      DateTime.diff(now, first.sent_at) < @wait -> {member, :too_soon}
      true -> %{member: member, round: 2, first: first}
    end
  end

  @doc """
  Queues the emails plan/3 has for the members in `member_ids`, from `user`, each its own
  round. Ids the plan doesn't have are ignored. `{:ok, reminders}`, each queued, or
  `{:error, reason}`: `:none_selected`, `:deleted`, or `:started`.
  """
  def call(
        %Team{} = team,
        %Activity{team_id: team_id} = activity,
        %User{} = user,
        member_ids,
        now
      )
      when team_id == team.id do
    ids = MapSet.new(member_ids)

    cond do
      activity.deleted_at ->
        {:error, :deleted}

      not DateTime.before?(now, activity.started_at) ->
        {:error, :started}

      MapSet.size(ids) == 0 ->
        {:error, :none_selected}

      true ->
        {:ok, queue_picked(activity, user, ids, now)}
    end
  end

  defp queue_picked(activity, user, ids, now) do
    %{send: emails} = plan(invited_rows(activity), Reminder.for_activity(activity), now)

    for email <- emails,
        MapSet.member?(ids, email.member.id),
        reminder <- queue(activity, email, user, now),
        do: reminder
  end

  @doc "What a call/5 error says."
  def error_text(:none_selected), do: "Select at least 1 member to email."
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
  defp queue(activity, %{member: member, round: round}, user, now) do
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
