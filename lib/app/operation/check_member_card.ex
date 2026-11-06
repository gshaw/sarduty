defmodule App.Operation.CheckMemberCard do
  alias App.Model.DemoTeam
  alias App.Model.MemberCard
  alias App.Operation.BuildCardQualifications

  @doc """
  The verify site's answer for one stored code: the page (Web.VerifyLive) and the JSON
  check (Web.CardApiController) both ask here. `%{status: :not_found, sample:, code:}` when
  no card has it, else `%{status:, card:, sample:, qualifications:}`, with qualifications
  only for an active card. A sample card's code (#854) is looked up in Coast Range SAR's
  own database, never the real one. A Try a demo team's card is a sample too: a visitor
  made it (#857).
  """
  def call(code, now \\ DateTime.utc_now()) do
    sample? = MemberCard.sample_code?(code)
    repo = if sample?, do: App.SampleRepo, else: App.Repo

    case MemberCard.find_by_code(code, repo) do
      %MemberCard{} = card ->
        status = MemberCard.status(card, now, repo)

        %{
          status: status,
          card: card,
          sample: sample? or DemoTeam.demo?(card.member.team_id),
          qualifications: qualifications(status, card, now, repo)
        }

      nil ->
        %{status: :not_found, sample: sample?, code: code}
    end
  end

  defp qualifications(:active, %MemberCard{member: member}, now, repo),
    do: BuildCardQualifications.call(member.team, member, now, repo)

  defp qualifications(_status, _card, _now, _repo), do: []
end
