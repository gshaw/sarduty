defmodule Web.CardApiJson do
  @moduledoc """
  The JSON check's answer for one card (Web.CardApiController), so the doc's sample cards
  (Web.CardApiDoc) show exactly what the check sends. Apps hold the field names: add
  fields but never rename or remove one; a change that breaks them is /api/v2.

  It says what the page says, plus where an active member's records live and their IDs
  there, which open nothing without the team's own access key.
  """

  alias App.Adapter.D4H
  alias App.Model.MemberCard

  @doc "A CheckMemberCard result as `{http_status, body}`."
  def answer(%{status: :not_found}), do: {404, %{status: "not_found"}}

  def answer(%{status: :revoked, card: card, sample: sample}) do
    {200, %{code: MemberCard.format_code(card.code), status: "revoked", sample: sample}}
  end

  # A former member's card gives the name, the team, and when they left, as the page does,
  # and no photo, qualifications, or IDs (#176).
  def answer(%{status: :inactive, card: card, sample: sample}) do
    member = card.member

    {200,
     %{
       code: MemberCard.format_code(card.code),
       status: "inactive",
       sample: sample,
       member: %{name: member.name, left_at: time(member.left_at)},
       team: team_json(member.team, nil)
     }}
  end

  def answer(%{status: :active, card: card} = result) do
    member = card.member
    team = member.team
    code = MemberCard.format_code(card.code)

    {200,
     %{
       code: code,
       status: "active",
       sample: result.sample,
       member: %{
         name: member.name,
         joined_at: time(member.joined_at),
         photo_url: Web.VerifyHost.url() <> "/" <> code <> "/photo",
         qualifications:
           Enum.map(result.qualifications, &%{name: &1.name, ends_at: time(&1.ends_at)})
       },
       team: team_json(team, MemberCard.valid_until(team)),
       records: %{
         service: service(team),
         api_url: team.d4h_api_host && "https://" <> team.d4h_api_host,
         team_id: team.d4h_team_id,
         member_id: member.d4h_member_id
       }
     }}
  end

  defp team_json(team, valid_until) do
    %{
      name: team.name,
      organization: team.organization && team.organization.name,
      refreshed_at: time(team.d4h_refreshed_at),
      valid_until: time(valid_until)
    }
  end

  # The API's own names, so renaming D4H.service/1's atoms never breaks an app.
  defp service(team) do
    case D4H.service(team) do
      :d4h -> "d4h"
      :records -> "sar_duty_records"
    end
  end

  # Every time in whole seconds, so each one reads the same way.
  defp time(nil), do: nil
  defp time(%DateTime{} = time), do: DateTime.truncate(time, :second)
end
