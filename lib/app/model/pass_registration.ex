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
    field :push_token, :string
    timestamps(type: :utc_datetime_usec)
  end

  # A member's cards share one Wallet serial, and a phone registers once per serial: when
  # a replacement pass lands on the same pass, Wallet doesn't register again. So a
  # registration counts for every card with its card's serial.

  @doc "`:created`, or `:existing` when the phone already had the pass (its token is updated)."
  def register!(%MemberCard{} = card, device, push_token) do
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
  def unregister!(%MemberCard{serial_number: serial_number}, device) do
    card_ids = MemberCard |> where([c], c.serial_number == ^serial_number) |> select([c], c.id)

    PassRegistration
    |> where(
      [r],
      r.member_card_id in subquery(card_ids) and r.device_library_identifier == ^device
    )
    |> Repo.delete_all()
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
