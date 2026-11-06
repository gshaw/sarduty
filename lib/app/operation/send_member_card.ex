defmodule App.Operation.SendMemberCard do
  @moduledoc """
  Gets a member their ID card by email (#893). Issue and Replace on the ID Card tab make
  a new card here and queue its email; Email card queues the current card's again. Every
  member gets a card makes each member's card the same way, all at once, and queues
  their emails behind the team admin's clicks (App.Operation.IssueEveryMemberCard).
  Each email is one App.Worker.SendMemberCardWorker job.

  The card's `email_status` says whether its email went: `:sending` while the job waits,
  then `:sent` or `:failed`. The job sends only a card marked sending, so a job that runs
  twice, or a second queued for the same card, sends one email.
  """

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.EmailMemberCard
  alias App.Operation.IssueMemberCard
  alias App.Repo
  alias App.Worker.SendMemberCardWorker

  # Oban runs the lowest number first. A rollout's emails go after a team admin's clicks
  # and after reminders and letters, which keep the default 0.
  @rollout_priority 3

  @doc """
  Issue or Replace: a new card with a new code (IssueMemberCard), and its email queued
  when the member has an address. The old card stops working. `{:ok, card}`, or
  IssueMemberCard's error.
  """
  def issue(%Team{} = team, %Member{} = member, now) do
    Repo.transaction(fn ->
      case IssueMemberCard.call(team, member, now) do
        {:ok, card} -> queue_email(card, member, now, click(now))
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Every member gets a card: a new card for a member who has none, and its email queued
  behind any click. Call it in the rollout's transaction. `{:ok, card}`, or
  IssueMemberCard's error.
  """
  def issue_in_rollout(%Team{} = team, %Member{} = member, now) do
    with {:ok, card} <- IssueMemberCard.call(team, member, now) do
      {:ok, queue_email(card, member, now, priority: @rollout_priority)}
    end
  end

  @doc """
  Email card: queues the current card's email again. `{:ok, card}`, or
  `{:error, :no_email}` or `{:error, :no_card}`.
  """
  def email(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    cond do
      not email?(member) ->
        {:error, :no_email}

      card = MemberCard.find_current(team, member) ->
        Repo.transaction(fn -> queue(card, member, now, click(now)) end)

      true ->
        {:error, :no_card}
    end
  end

  @doc """
  The job's work: the member's current card's email, if it waits for one. `last?` is the
  job's last attempt, when a refusal marks the email failed. `{:cancel, reason}` when
  only a person can fix it: no card (ID cards turned off, or the member gone) or no
  email.
  """
  def deliver(team_id, member_id, last?, now) do
    with %Team{} = team <- Team.get(team_id),
         %Member{} = member <- Member.find(team, member_id),
         %MemberCard{} = card <- MemberCard.find_current(team, member) do
      send_if_waiting(card, team, member, last?, now)
    else
      nil -> {:cancel, "no card"}
    end
  end

  defp send_if_waiting(%MemberCard{email_status: :sending} = card, team, member, last?, now) do
    case EmailMemberCard.call(team, member, now) do
      :ok ->
        finish(card, member, :sent, now)
        :ok

      {:error, :no_email} ->
        finish(card, member, :failed, now)
        {:cancel, "the member has no email"}

      {:error, reason} ->
        if last?, do: finish(card, member, :failed, now)
        {:error, reason}
    end
  end

  defp send_if_waiting(_card, _team, _member, _last?, _now), do: :ok

  defp queue_email(card, member, now, opts) do
    if email?(member), do: queue(card, member, now, opts), else: card
  end

  defp queue(card, member, now, opts) do
    card = MemberCard.set_email_status!(card, :sending, now)
    SendMemberCardWorker.enqueue(member, opts)
    card
  end

  # A click sends now, ahead of a rollout. A job already waiting for this member, a retry
  # or their rollout email, is moved to now and to the front rather than left to send
  # later while the tab says Sending. Oban replaces only what the new job sets, so it
  # names both.
  defp click(now) do
    [
      scheduled_at: now,
      priority: 0,
      replace: [
        available: [:priority],
        scheduled: [:scheduled_at, :priority],
        retryable: [:scheduled_at, :priority]
      ]
    ]
  end

  defp finish(card, member, status, now) do
    MemberCard.set_email_status!(card, status, now)
    broadcast(member)
  end

  defp email?(%Member{email: email}), do: email not in [nil, ""]

  # The member's ID Card tab shows the new card or how its email went.
  defp broadcast(member),
    do: Phoenix.PubSub.broadcast(App.PubSub, MemberCard.pass_topic(member.id), :card_changed)
end
