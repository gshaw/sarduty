defmodule App.Worker.UpdateCancelledCardWorker do
  @moduledoc """
  Tells Wallet a card was cancelled: a push to each phone holding its Apple pass, and
  its Google pass sent again, so it stops looking valid there. One job per card, queued
  with the cancel. A failed Google update is tried again, since nothing else would send
  it: the refresh only sends live cards. A failed push isn't, since the phone checks by
  itself.
  """

  use Oban.Worker, queue: :bulk, max_attempts: 3

  alias App.Model.MemberCard
  alias App.Operation.PushPassUpdates
  alias App.Operation.UpdateGooglePasses

  @doc "Queues a job per cancelled card. Call it in the transaction that cancels them."
  def enqueue_all(cards) do
    cards |> Enum.map(&new(%{member_card_id: &1.id})) |> Oban.insert_all()
    cards
  end

  # After 5, then 10 minutes.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 5 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"member_card_id" => id}}) do
    case MemberCard.get_revoked(id) do
      nil ->
        {:cancel, "no cancelled card"}

      card ->
        PushPassUpdates.push_cards([card])
        UpdateGooglePasses.update_cards([card], DateTime.utc_now())
    end
  end
end
