defmodule App.Operation.EmailMemberCard do
  alias App.Mailer.MemberCardMailer
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.BuildApplePass
  alias App.Repo

  @doc "Emails the member their current card as an Apple Wallet pass."
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    cond do
      member.email in [nil, ""] -> {:error, :no_email}
      card = MemberCard.find_current(team, member) -> send_pass(card, now)
      true -> {:error, :no_card}
    end
  end

  defp send_pass(card, now) do
    card = Repo.preload(card, member: :team)

    with {:ok, pkpass} <- BuildApplePass.call(card, now),
         {:ok, _metadata} <- MemberCardMailer.deliver(card, pkpass) do
      :ok
    end
  end
end
