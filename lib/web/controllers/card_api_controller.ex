defmodule Web.CardApiController do
  use Web, :controller

  alias App.Adapter.D4H
  alias App.Model.MemberCard
  alias App.Operation.CheckMemberCard
  alias Web.VerifyLimit

  # The verify site's check as JSON, for apps that sign members in by scanning their card
  # (SAR Command Assist first). /agents/id-cards documents it; keep the two in step.
  # It says what the page says and no more, plus where the team's records live: D4H or SAR
  # Duty Records, which serve the same API. The IDs open nothing without the team's own
  # access key. Misses count toward the page's limit (Web.VerifyLimit).
  def show(conn, %{"code" => input}) do
    ip = VerifyLimit.client_ip(conn)
    code = MemberCard.normalize_code(input)
    conn = put_resp_header(conn, "cache-control", "no-store")

    cond do
      is_binary(code) and MemberCard.sample_code?(code) ->
        answer(conn, CheckMemberCard.call(code))

      VerifyLimit.limited?(ip) ->
        conn |> put_status(:too_many_requests) |> json(%{status: "limited"})

      is_nil(code) ->
        VerifyLimit.miss(ip)
        not_found(conn)

      true ->
        result = CheckMemberCard.call(code)
        if result.status == :not_found, do: VerifyLimit.miss(ip)
        answer(conn, result)
    end
  end

  defp answer(conn, %{status: :not_found}), do: not_found(conn)

  defp answer(conn, %{status: :revoked, card: card, sample: sample}) do
    json(conn, %{code: MemberCard.format_code(card.code), status: "revoked", sample: sample})
  end

  defp answer(conn, %{status: status, card: card} = result) do
    member = card.member
    team = member.team
    code = MemberCard.format_code(card.code)

    json(conn, %{
      code: code,
      status: Atom.to_string(status),
      sample: result.sample,
      member: member_json(status, member, code, result.qualifications),
      team: %{
        name: team.name,
        organization: team.organization && team.organization.name,
        refreshed_at: team.d4h_refreshed_at,
        valid_until: if(status == :active, do: MemberCard.valid_until(team))
      },
      records: %{
        service: team |> D4H.service() |> Atom.to_string(),
        api_url: team.d4h_api_host && "https://" <> team.d4h_api_host,
        team_id: team.d4h_team_id,
        member_id: member.d4h_member_id
      }
    })
  end

  # A former member's card gives the name and when they left, as the page does (#176).
  defp member_json(:active, member, code, qualifications) do
    %{
      name: member.name,
      joined_at: member.joined_at,
      photo_url: Web.VerifyHost.url() <> "/" <> code <> "/photo",
      qualifications: Enum.map(qualifications, &Map.take(&1, [:name, :ends_at]))
    }
  end

  defp member_json(:inactive, member, _code, _qualifications) do
    %{name: member.name, left_at: member.left_at}
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{status: "not_found"})
end
