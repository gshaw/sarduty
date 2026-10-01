defmodule App.Operation.EmailMemberCard do
  alias App.Mailer.MemberCardMailer
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Repo

  @doc """
  Emails the member their current card: an Apple Wallet pass and a Google Wallet link,
  whichever are set up.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    cond do
      member.email in [nil, ""] -> {:error, :no_email}
      card = MemberCard.find_current(team, member) -> send_pass(card, now)
      true -> {:error, :no_card}
    end
  end

  defp send_pass(card, now) do
    card = Repo.preload(card, member: :team)

    with {:ok, pkpass} <-
           optional(BuildApplePass.configured?(), &BuildApplePass.call/2, card, now),
         {:ok, google_url} <-
           optional(BuildGooglePass.configured?(), &BuildGooglePass.call/2, card, now),
         {:ok, _metadata} <- MemberCardMailer.deliver(card, pkpass, google_url) do
      :ok
    end
  end

  defp optional(true, build, card, now), do: build.(card, now)
  defp optional(false, _build, _card, _now), do: {:ok, nil}
end
