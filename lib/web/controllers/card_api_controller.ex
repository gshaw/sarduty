defmodule Web.CardApiController do
  use Web, :controller

  alias App.Adapter.D4H
  alias App.Model.MemberCard
  alias App.Operation.CheckMemberCard
  alias Web.VerifyLimit

  # The verify site's check as JSON, for apps that sign members in by scanning their card
  # (#299). /agents/id-cards documents it (Web.CardApiDoc); keep the two in step. Apps
  # hold the URL and the field names, so add fields but never rename or remove one: a
  # change that breaks them is /api/v2.
  #
  # It says what the page says, plus where an active member's records live and their IDs
  # there, which open nothing without the team's own access key. Misses count toward the
  # page's limit (Web.VerifyLimit).
  def show(conn, %{"code" => input}) do
    ip = VerifyLimit.client_ip(conn)
    code = MemberCard.normalize_code(input)
    conn = put_resp_header(conn, "cache-control", "no-store")

    cond do
      is_binary(code) and MemberCard.sample_code?(code) ->
        answer(conn, CheckMemberCard.call(code))

      VerifyLimit.limited?(ip) ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(VerifyLimit.retry_after()))
        |> put_status(:too_many_requests)
        |> json(%{status: "limited"})

      is_nil(code) ->
        not_found(conn)

      true ->
        result = CheckMemberCard.call(code)
        if result.status == :not_found, do: VerifyLimit.miss(ip, code)
        answer(conn, result)
    end
  end

  defp answer(conn, %{status: :not_found}), do: not_found(conn)

  defp answer(conn, %{status: :revoked, card: card, sample: sample}) do
    json(conn, %{code: MemberCard.format_code(card.code), status: "revoked", sample: sample})
  end

  # A former member's card gives the name, the team, and when they left, as the page does,
  # and no photo, qualifications, or IDs (#176).
  defp answer(conn, %{status: :inactive, card: card, sample: sample}) do
    member = card.member

    json(conn, %{
      code: MemberCard.format_code(card.code),
      status: "inactive",
      sample: sample,
      member: %{name: member.name, left_at: time(member.left_at)},
      team: team_json(member.team, nil)
    })
  end

  defp answer(conn, %{status: :active, card: card} = result) do
    member = card.member
    team = member.team
    code = MemberCard.format_code(card.code)

    json(conn, %{
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
    })
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

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{status: "not_found"})
end
