defmodule App.Operation.IssueMemberCard do
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Repo

  @doc "Gives the member a new card with a new code. Any card they had stops working."
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    Repo.transaction(fn ->
      MemberCard.revoke_all!(team, member, now)

      MemberCard.insert!(%MemberCard{
        team_id: team.id,
        member_id: member.id,
        code: MemberCard.generate_code()
      })
    end)
  end
end
