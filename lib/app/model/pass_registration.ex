defmodule App.Model.PassRegistration do
  use App, :model

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Repo

  # A phone that holds a card's Apple Wallet pass. Wallet registers it when the pass
  # is added, and SAR Duty sends a push to its token when the pass changes.
  schema "pass_registrations" do
    belongs_to :member_card, MemberCard
    field :device_library_identifier, :string
    field :push_token, :string, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  # A member's cards share one Wallet serial, and a phone registers once per serial: when
  # a replacement pass lands on the same pass, Wallet doesn't register again. So a
  # registration counts for every card with its card's serial.

  @doc "`:created`, or `:existing` when the phone already had the pass (its token is updated)."
  def register!(%MemberCard{} = card, device, push_token) do
    result = insert_or_update(card, device, push_token)
    MemberCard.broadcast_wallet_changed(card.member_id)
    result
  end

  defp insert_or_update(card, device, push_token) do
    case card
         |> for_serial()
         |> where([r], r.device_library_identifier == ^device)
         |> Repo.all() do
      [] ->
        Repo.insert!(%PassRegistration{
          member_card_id: card.id,
          device_library_identifier: device,
          push_token: push_token
        })

        :created

      registrations ->
        Enum.each(registrations, &(&1 |> change(push_token: push_token) |> Repo.update!()))
        :existing
    end
  end

  # SQLite can't DELETE with a JOIN, so the serial's cards go in as a subquery.
  def unregister!(%MemberCard{serial_number: serial_number} = card, device) do
    card_ids = MemberCard |> where([c], c.serial_number == ^serial_number) |> select([c], c.id)

    result =
      PassRegistration
      |> where(
        [r],
        r.member_card_id in subquery(card_ids) and r.device_library_identifier == ^device
      )
      |> Repo.delete_all()

    MemberCard.broadcast_wallet_changed(card.member_id)
    result
  end

  @doc """
  How many devices hold this card's own pass, as far as SAR Duty knows (#952). See
  `holding/2`.
  """
  def count_holding(%MemberCard{} = card), do: holding(card, get_all_for_serial(card))

  @doc """
  How many of the serial's registrations hold this card, given them all. A device that
  registered this card holds it. A replacement shares its serial with the card before it,
  and Wallet doesn't register again when one lands on the same pass (#70), so with none
  of its own a card counts the serial's devices once a phone fetched its pass: a fetch
  carries the card's own token. Until then they hold the cancelled card. Once a device
  registered the replacement, the others don't count, as a lost phone still holds the
  cancelled card.
  """
  def holding(%MemberCard{id: id} = card, registrations) do
    own = Enum.count(registrations, &(&1.member_card_id == id))

    cond do
      own > 0 -> own
      card.pass_fetched_at -> length(registrations)
      true -> 0
    end
  end

  @doc "Every phone holding a pass with this card's serial, whichever card it was added as."
  def get_all_for_serial(%MemberCard{} = card), do: card |> for_serial() |> Repo.all()

  @doc "The cards whose serial is registered on a phone, changed after `since` if given."
  def cards_for_device(device, since) do
    serials =
      PassRegistration
      |> join(:inner, [r], c in MemberCard, on: c.id == r.member_card_id)
      |> where([r], r.device_library_identifier == ^device)
      |> select([r, c], c.serial_number)

    MemberCard
    |> where([c], c.serial_number in subquery(serials))
    |> maybe_since(since)
    |> Repo.all()
  end

  defp for_serial(%MemberCard{serial_number: serial_number}) do
    PassRegistration
    |> join(:inner, [r], c in MemberCard, on: c.id == r.member_card_id)
    |> where([r, c], c.serial_number == ^serial_number)
  end

  defp maybe_since(query, nil), do: query
  defp maybe_since(query, since), do: where(query, [c], c.pass_updated_at > ^since)

  def delete!(%PassRegistration{} = registration), do: Repo.delete!(registration)
end
