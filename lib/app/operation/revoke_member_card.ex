defmodule App.Operation.RevokeMemberCard do
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team

  @doc "Stops the member's card from verifying. The code is never reused."
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    MemberCard.revoke_all!(team, member, now)
    :ok
  end
end
