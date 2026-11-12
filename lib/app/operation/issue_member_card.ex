defmodule App.Operation.IssueMemberCard do
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.UpdateCancelledCardWorker

  @doc """
  Gives the member a new card with a new code and token, under their existing Wallet
  serial number: Issue, or Replace for a lost phone. Any card they had stops working,
  and a job per card tells phones holding its pass to fetch the voided one. Adding the
  new pass replaces the old one in Apple Wallet; in Google Wallet the old one expires.
  SendMemberCard emails it.

  `{:error, :id_cards_off}` unless a SAR Duty admin turned ID cards on for the team, and
  `{:error, :not_active}` for a member not in good standing (retired or retiring), whose
  card would only verify as not active. `{:error, :no_photo}` for a member with no photo
  at the last check (#1012): a checker compares the photo, so a card without one proves
  nothing. The ID Card tab checks live first (App.Operation.CheckMemberPhoto).
  """
  def call(%Team{id_cards_enabled: false}, %Member{}, _now), do: {:error, :id_cards_off}

  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    cond do
      not Member.good_standing?(member, now) -> {:error, :not_active}
      not member.has_photo -> {:error, :no_photo}
      true -> issue(team, member, now)
    end
  end

  defp issue(team, member, now) do
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
