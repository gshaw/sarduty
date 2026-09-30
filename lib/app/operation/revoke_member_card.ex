defmodule App.Operation.RevokeMemberCard do
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.PushPassUpdates

  @doc """
  Stops the member's card from verifying, and tells phones holding its pass to fetch
  the voided one. The code is never reused.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    team |> MemberCard.revoke_all!(member, now) |> PushPassUpdates.push_cards()
  end
end
