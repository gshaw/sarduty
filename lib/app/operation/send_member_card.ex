defmodule App.Operation.SendMemberCard do
  @moduledoc """
  Gets a member their ID card by email (#893). Issue and Replace on the ID Card tab make
  a new card here and queue its email; Email card queues the current card's again. Each
  is one App.Worker.SendMemberCardWorker job, which also makes the card when the member
  has none, so a rollout can queue the same job for every member.

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

  @doc """
  Issue or Replace: a new card with a new code (IssueMemberCard), and its email queued
  when the member has an address. The old card stops working. `{:ok, card}`, or
  IssueMemberCard's error.
  """
  def issue(%Team{} = team, %Member{} = member, now) do
    Repo.transaction(fn ->
      case IssueMemberCard.call(team, member, now) do
        {:ok, card} -> queue_email(card, member, now)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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
        Repo.transaction(fn -> queue(card, member, now) end)

      true ->
        {:error, :no_card}
    end
  end

  @doc """
  The job's work: the member's current card, made now if they have none, then its email
  if it waits for one. `last?` is the job's last attempt, when a refusal marks the email
  failed. `{:cancel, reason}` when only a person can fix it: ID cards off, a member not
  in good standing, or no email.
  """
  def deliver(team_id, member_id, last?, now) do
    with %Team{} = team <- Team.get(team_id),
         %Member{} = member <- Member.find(team, member_id),
         {:ok, card} <- current_or_new(team, member, now) do
      send_if_waiting(card, team, member, last?, now)
    else
      nil -> {:cancel, "no member"}
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp current_or_new(team, member, now) do
    case MemberCard.find_current(team, member) do
      nil -> new_card(team, member, now)
      card -> {:ok, card}
    end
  end

  defp new_card(team, member, now) do
    with {:ok, card} <- IssueMemberCard.call(team, member, now) do
      card = if email?(member), do: MemberCard.set_email_status!(card, :sending, now), else: card
      broadcast(member)
      {:ok, card}
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

  defp queue_email(card, member, now) do
    if email?(member), do: queue(card, member, now), else: card
  end

  # A click sends now. A job already waiting for this member, a retry or a rollout slot,
  # is moved to now rather than left to send later while the tab says Sending. Oban
  # replaces only what the new job sets, so it names scheduled_at.
  defp queue(card, member, now) do
    card = MemberCard.set_email_status!(card, :sending, now)

    SendMemberCardWorker.enqueue(member,
      scheduled_at: now,
      replace: [scheduled: [:scheduled_at], retryable: [:scheduled_at]]
    )

    card
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
