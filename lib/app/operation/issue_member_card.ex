defmodule App.Operation.IssueMemberCard do
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.PushPassUpdates
  alias App.Repo

  @doc """
  Gives the member a new card with a new code. Any card they had stops working, and
  phones holding its pass are told to fetch the voided one.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    {:ok, {card, revoked}} =
      Repo.transaction(fn ->
        revoked = MemberCard.revoke_all!(team, member, now)

        card =
          MemberCard.insert!(%MemberCard{
            team_id: team.id,
            member_id: member.id,
            code: MemberCard.generate_code(),
            authentication_token: MemberCard.generate_authentication_token(),
            pass_updated_at: now
          })

        {card, revoked}
      end)

    PushPassUpdates.push_cards(revoked)
    {:ok, card}
  end
end
