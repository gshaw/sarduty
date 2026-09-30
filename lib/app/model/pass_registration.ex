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

  @doc "`:created`, or `:existing` when the phone already had it (its token is updated)."
  def register!(%MemberCard{} = card, device, push_token) do
    case Repo.get_by(PassRegistration, member_card_id: card.id, device_library_identifier: device) do
      nil ->
        Repo.insert!(%PassRegistration{
          member_card_id: card.id,
          device_library_identifier: device,
          push_token: push_token
        })

        :created

      registration ->
        registration |> change(push_token: push_token) |> Repo.update!()
        :existing
    end
  end

  def unregister!(%MemberCard{} = card, device) do
    PassRegistration
    |> where([r], r.member_card_id == ^card.id and r.device_library_identifier == ^device)
    |> Repo.delete_all()
  end

  def get_all_for_card(%MemberCard{} = card) do
    PassRegistration |> where([r], r.member_card_id == ^card.id) |> Repo.all()
  end

  @doc "The cards registered on a phone, for its pass type, changed after `since` if given."
  def cards_for_device(device, since) do
    MemberCard
    |> join(:inner, [c], r in PassRegistration, on: r.member_card_id == c.id)
    |> where([c, r], r.device_library_identifier == ^device)
    |> maybe_since(since)
    |> Repo.all()
  end

  defp maybe_since(query, nil), do: query
  defp maybe_since(query, since), do: where(query, [c], c.pass_updated_at > ^since)

  def delete!(%PassRegistration{} = registration), do: Repo.delete!(registration)
end
