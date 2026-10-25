defmodule App.Operation.IssueMemberCard do
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.UpdateCancelledCardWorker

  @doc """
  Gives the member a new card with a new code and token, under their existing Wallet
  serial number. Any card they had stops working, and a job per card tells phones
  holding its pass to fetch the voided one. Adding the new pass replaces the old one in Apple Wallet; in
  Google Wallet the old one expires.

  `{:error, :id_cards_off}` unless a SAR Duty admin turned ID cards on for the team.
  """
  def call(%Team{id_cards_enabled: false}, %Member{}, _now), do: {:error, :id_cards_off}

  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    {:ok, card} =
      Repo.transaction(fn ->
        serial_number = MemberCard.next_serial_number(team, member)
        team |> MemberCard.revoke_all!(member, now) |> UpdateCancelledCardWorker.enqueue_all()

        MemberCard.insert!(%MemberCard{
          team_id: team.id,
          member_id: member.id,
          code: MemberCard.generate_code(),
          authentication_token: MemberCard.generate_authentication_token(),
          serial_number: serial_number,
          pass_updated_at: now
        })
      end)

    {:ok, card}
  end
end
