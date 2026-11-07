defmodule App.Model.PassRegistrationTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.IssueMemberCard

  @now ~U[2026-11-07 20:00:00.000000Z]

  setup do
    team = team_fixture()
    member = member_fixture(team)
    %{team: team, member: member, card: member_card_fixture(member)}
  end

  test "a phone that registered the card holds it", %{card: card} do
    assert PassRegistration.count_holding(card) == 0
    PassRegistration.register!(card, "device-1", "push-1")
    PassRegistration.register!(card, "device-2", "push-2")
    assert PassRegistration.count_holding(card) == 2
    assert MemberCard.in_wallet?(card)
  end

  # A replacement shares the serial, and Wallet doesn't register it again (#70), so the
  # phones still hold the cancelled card until one fetches the replacement's pass.
  test "a replacement counts the phones only once one fetched its pass",
       %{team: team, member: member, card: card} do
    PassRegistration.register!(card, "device-1", "push-1")
    {:ok, replacement} = IssueMemberCard.call(team, member, @now)

    assert PassRegistration.count_holding(replacement) == 0
    refute MemberCard.in_wallet?(replacement)

    replacement = MemberCard.record_pass_fetched!(replacement, @now)
    assert PassRegistration.count_holding(replacement) == 1
    assert MemberCard.in_wallet?(replacement)
  end
end
