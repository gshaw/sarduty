defmodule App.Operation.EmailMemberCard do
  alias App.Mailer.MemberCardMailer
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Repo

  @doc """
  Emails the member a link to their current card's page (#952). It builds no pass: the
  page builds one when the member taps Add to Apple Wallet or Add to Google Wallet.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member) when team_id == team.id do
    cond do
      member.email in [nil, ""] -> {:error, :no_email}
      card = MemberCard.find_current(team, member) -> send_link(card)
      true -> {:error, :no_card}
    end
  end

  defp send_link(card) do
    card = Repo.preload(card, member: :team)

    with {:ok, _metadata} <- MemberCardMailer.deliver(card, Web.CardLinks.url(card)) do
      :ok
    end
  end
end
