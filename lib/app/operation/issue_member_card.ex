defmodule App.Operation.IssueMemberCard do
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.PushPassUpdates
  alias App.Operation.UpdateGooglePasses
  alias App.Repo

  @doc """
  Gives the member a new card with a new code and token, under their existing Wallet
  serial number. Any card they had stops working, and phones holding its pass are told
  to fetch the voided one. Adding the new pass replaces the old one in Apple Wallet; in
  Google Wallet the old one expires.

  `{:error, :id_cards_off}` unless a SAR Duty admin turned ID cards on for the team.
  """
  def call(%Team{id_cards_enabled: false}, %Member{}, _now), do: {:error, :id_cards_off}

  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    {:ok, {card, revoked}} =
      Repo.transaction(fn ->
        serial_number = MemberCard.next_serial_number(team, member)
        revoked = MemberCard.revoke_all!(team, member, now)

        card =
          MemberCard.insert!(%MemberCard{
            team_id: team.id,
            member_id: member.id,
            code: MemberCard.generate_code(),
            authentication_token: MemberCard.generate_authentication_token(),
            serial_number: serial_number,
            pass_updated_at: now
          })

        {card, revoked}
      end)

    PushPassUpdates.push_cards(revoked)
    UpdateGooglePasses.update_cards(revoked, now)
    {:ok, card}
  end
end
