defmodule App.Operation.RevokeMemberCard do
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.PushPassUpdates
  alias App.Operation.UpdateGooglePasses

  @doc """
  Stops the member's card from verifying, and tells phones holding its pass to fetch
  the voided one. Google Wallet passes expire. The code is never reused.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    cards = MemberCard.revoke_all!(team, member, now)
    PushPassUpdates.push_cards(cards)
    UpdateGooglePasses.update_cards(cards, now)
  end
end
