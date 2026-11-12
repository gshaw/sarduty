defmodule App.Worker.UpdateCardWorker do
  @moduledoc """
  Sends one card to the phones that hold it, live or cancelled: a push to each phone
  with its Apple pass, so the phone downloads it again, and its Google pass sent again
  if it changed. Every pass update goes through here, one job per card.

  Many cards at once go out 6 seconds apart, about 10 a minute. Each push makes a phone
  download its pass, which reads the database and fetches the photo from D4H. On
  2026-11-12 the first nightly photo check pushed 66 cards at once, and the downloads
  used up the database pool for 5 minutes.

  A failed Google update is tried again, since nothing else would send it. A failed push
  isn't, since the phone checks by itself.
  """

  use Oban.Worker, queue: :bulk, max_attempts: 3

  alias App.Model.MemberCard
  alias App.Operation.PushPassUpdates
  alias App.Operation.UpdateGooglePasses

  @spacing_seconds 6

  @doc "Queues a job for the card, to run now."
  def enqueue(%MemberCard{} = card), do: enqueue_all([card])

  @doc """
  Queues a job per card, the first now and each next one 6 seconds later. Call it in the
  transaction that changed them. Returns the cards.
  """
  def enqueue_all(cards) do
    cards
    |> Enum.with_index()
    |> Enum.map(fn {card, index} ->
      new(%{member_card_id: card.id}, schedule_in: index * @spacing_seconds)
    end)
    |> Oban.insert_all()

    cards
  end

  # After 5, then 10 minutes.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 5 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"member_card_id" => id}}) do
    case MemberCard.get_with_member(id) do
      nil ->
        {:cancel, "no card"}

      card ->
        PushPassUpdates.push_card(card)
        UpdateGooglePasses.update_cards([card], DateTime.utc_now())
    end
  end
end
