defmodule App.Operation.SendTestPassUpdate do
  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.PushPassUpdates

  @doc """
  Pushes a harmless change to the phones that hold the card's Apple pass, so a manager
  can see updates still reach them. The pass gains a "Test update" time on the back,
  which the fingerprint leaves out. Returns how many phones were pushed to.
  """
  def call(%MemberCard{} = card, now) do
    card = MemberCard.record_test_update!(card, now)
    phones = PassRegistration.get_all_for_serial(card)
    PushPassUpdates.push_cards([card])
    {:ok, length(phones)}
  end
end
