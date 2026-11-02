defmodule App.Operation.SendActivityUpdate do
  @moduledoc """
  A team admin emails an update to members on an activity (#609), before it starts: their
  own message, to the members they leave checked, whatever their reply. Each email ends
  with where the member stands (ActivityMailer.update_ending/2): reply buttons for a
  member with no reply, unless they turned invitation reminders off, and a link to
  change the reply for the rest. Asking only members with no reply is Send reminders.

  plan/1 says who can get one, pure. call/6 records a queued row per update with its
  job, in one transaction. App.Worker.SendActivityUpdateWorker then sends each with
  deliver/3, retrying a refusal. Remove members (#704) queues its message to a signed up
  member here too, as a `:removal`.
  """
  alias App.Accounts.User
  alias App.Mailer.ActivityMailer
  alias App.Model.Activity
  alias App.Model.ActivityUpdate
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.SendReminders
  alias App.Repo
  alias App.Validate.Message
  alias App.ViewData.ActivityMembers
  alias App.Worker.SendActivityUpdateWorker

  @doc """
  Who can get an update, from the activity's rows (ActivityMembers.load/1, one per
  member, in its order):

    * `groups`: `[{status, [row]}]` for each D4H status with a member who has an email,
      in ActivityMembers' order.
    * `no_email`: the members with no email, by name.
  """
  def plan(rows) do
    {can, no_email} = Enum.split_with(rows, &(&1.member.email not in [nil, ""]))

    groups =
      for status <- ActivityMembers.statuses(),
          group = Enum.filter(can, &(&1.status == status)),
          group != [],
          do: {status, group}

    %{groups: groups, no_email: Enum.map(no_email, & &1.member)}
  end

  @doc """
  The activity's earlier sends, newest first, as `%{sent_at:, sent_by_user:, message:,
  members:, failed:}`. Removals are not updates, so they're left out.
  """
  def sent_before(updates) do
    updates
    |> Enum.filter(&(&1.kind == :update))
    |> Enum.group_by(& &1.sent_at)
    |> Enum.map(fn {sent_at, [first | _] = batch} ->
      %{
        sent_at: sent_at,
        sent_by_user: first.sent_by_user,
        message: first.message,
        members: length(batch),
        failed: Enum.count(batch, &(&1.status == :failed))
      }
    end)
    |> Enum.sort_by(& &1.sent_at, {:desc, DateTime})
  end

  @doc """
  Queues an update with `message` for each member in `member_ids` that plan/1 has, from
  `user`. Ids the plan doesn't have are ignored. `{:ok, updates}`, each queued, or
  `{:error, reason}`: `:no_message`, `:message_too_long`, `:none_selected`, `:deleted`,
  or `:started`.
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
      activity.deleted_at -> {:error, :deleted}
      Activity.started?(activity, now) -> {:error, :started}
      message == nil -> {:error, :no_message}
      not Message.fits?(message) -> {:error, :message_too_long}
      MapSet.size(ids) == 0 -> {:error, :none_selected}
      true -> {:ok, queue_picked(activity, user, ids, message, now)}
    end
  end

  defp queue_picked(activity, user, ids, message, now) do
    %{groups: groups} = activity |> ActivityMembers.load() |> plan()

    for {_status, rows} <- groups,
        row <- rows,
        MapSet.member?(ids, row.member.id),
        do: queue(activity, row.member, user, message, now, :update)
  end

  @doc "What a call/6 error says."
  def error_text(:no_message), do: "Enter a message."
  def error_text(:message_too_long), do: Message.error_text()
  def error_text(:none_selected), do: "Select at least 1 member to email."
  def error_text(:deleted), do: "This activity is deleted. Nothing can be sent to it."
  def error_text(:started), do: "Updates closed when the activity started."

  @doc """
  Records a queued `kind` email of `message` to `member` from `user`, with its job. The
  row and its job commit together, or neither does.
  """
  def queue(%Activity{} = activity, %Member{} = member, %User{} = user, message, now, kind)
      when kind in [:update, :removal] do
    {:ok, update} =
      Repo.transaction(fn ->
        update =
          Repo.insert!(%ActivityUpdate{
            team_id: activity.team_id,
            activity_id: activity.id,
            member_id: member.id,
            sent_by_user_id: user.id,
            message: message,
            sent_at: now,
            status: :queued,
            kind: kind
          })

        SendActivityUpdateWorker.enqueue(update)
        update
      end)

    update
  end

  @doc """
  Emails one queued update and marks it sent, for its job, ending with the member's reply
  as it is now. A refusal is `{:error, reason}`, so the job tries again; on the `last?`
  attempt the update is marked failed first. One no longer queued is `{:cancel,
  reason}`, and so is one whose activity started or was deleted, or whose member is no
  longer on it, before it went, which is marked failed. A removal goes whenever its job
  runs, unless the member is back on the activity by then.
  """
  def deliver(update_id, last?, now) do
    case ActivityUpdate.get_queued(update_id) do
      nil -> {:cancel, "no queued update"}
      update -> deliver_queued(update, last?, now)
    end
  end

  defp deliver_queued(%ActivityUpdate{kind: :removal} = update, last?, now) do
    if Attendance.invitation(update.activity, update.member) do
      ActivityUpdate.fail!(update, "The member was back on the activity before it went.")
      {:cancel, "the member is back on the activity"}
    else
      send_email(update, :removed, last?, now)
    end
  end

  defp deliver_queued(%ActivityUpdate{activity: activity, member: member} = update, last?, now) do
    invitation = Attendance.invitation(activity, member)

    cond do
      not Activity.open?(activity, now) ->
        ActivityUpdate.fail!(update, "The activity started before it went.")
        {:cancel, "the activity started"}

      invitation == nil or invitation.status not in ActivityMembers.statuses() ->
        ActivityUpdate.fail!(update, "The member left the activity before it went.")
        {:cancel, "the member left the activity"}

      true ->
        send_email(update, ActivityMailer.update_ending(invitation.status, member), last?, now)
    end
  end

  defp deliver_email(update, team, sender, :removed),
    do:
      ActivityMailer.deliver_removal(update.member, update.activity, team, sender, update.message)

  defp deliver_email(update, team, sender, ending),
    do:
      ActivityMailer.deliver_update(
        update.member,
        update.activity,
        team,
        sender,
        update.message,
        ending
      )

  defp send_email(%ActivityUpdate{team: team} = update, ending, last?, now) do
    sender = SendReminders.sender(team, update.sent_by_user, now)

    case deliver_email(update, team, sender, ending) do
      {:ok, _sent} ->
        ActivityUpdate.sent!(update)
        :ok

      {:error, error} ->
        if last?, do: ActivityUpdate.fail!(update, inspect(error))
        {:error, error}
    end
  end
end
