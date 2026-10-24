defmodule App.Operation.FindCertificateAward do
  @moduledoc """
  Whether D4H already has the award a certificate is for (#493): the member's award of
  the same qualification from the same day, read from D4H now, and whether it has a
  certificate. Then the team admin attaches the file to it, or declines, rather than
  adding a second award D4H's API could never remove.
  """

  alias App.Adapter.D4H
  alias App.Adapter.D4H.QualificationAward
  alias App.Model.Certificate
  alias App.Model.Team
  alias App.Repo

  @doc """
  `{:ok, nil}`, `{:ok, %{d4h_award_id:, starts_at:, ends_at:, certificate?:}}`, or
  `{:error, text}` when D4H can't be read.
  """
  def call(%Team{} = team, %Certificate{team_id: team_id} = certificate)
      when team_id == team.id do
    certificate = Repo.preload(certificate, [:member, :qualification])
    d4h = D4H.build_context_from_team(team)

    with %{} = qualification <- certificate.qualification,
         awards = D4H.fetch_member_awards(d4h, certificate.member.d4h_member_id),
         %{} = award <- match(awards, qualification.d4h_qualification_id, certificate.starts_on) do
      documents = D4H.fetch_award_documents(d4h, award.d4h_award_id)

      {:ok,
       %{
         d4h_award_id: award.d4h_award_id,
         starts_at: award.starts_at,
         ends_at: award.ends_at,
         certificate?: documents != []
       }}
    else
      nil -> {:ok, nil}
    end
  rescue
    error in [D4H.Error, Req.TransportError] -> {:error, Exception.message(error)}
  end

  @doc """
  Pure. The award of `d4h_qualification_id` that starts on `starts_on`
  (`QualificationAward.starts_on?/2`, as ApplyChangeSet checks it), or nil.
  """
  def match(awards, d4h_qualification_id, starts_on) do
    Enum.find(awards, fn award ->
      award.d4h_qualification_id == d4h_qualification_id and
        QualificationAward.starts_on?(award, starts_on)
    end)
  end
end
