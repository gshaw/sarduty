defmodule Web.CardApiController do
  use Web, :controller

  alias App.Model.MemberCard
  alias App.Operation.CheckMemberCard
  alias Web.CardApiJson
  alias Web.VerifyLimit

  # The verify site's check as JSON, for apps that sign members in by scanning their card
  # (#299). Web.CardApiJson builds the answer; /agents/id-cards documents it
  # (Web.CardApiDoc). Misses count toward the page's limit (Web.VerifyLimit).
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
        answer(conn, %{status: :not_found})

      true ->
        result = CheckMemberCard.call(code)
        if result.status == :not_found, do: VerifyLimit.miss(ip, code)
        answer(conn, result)
    end
  end

  defp answer(conn, result) do
    {status, body} = CardApiJson.answer(result)
    conn |> put_status(status) |> json(body)
  end
end
