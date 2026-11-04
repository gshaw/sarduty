defmodule Web.CardApiControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.MemberCard

  # The check as JSON on the verify site. Each test gets its own IP, since misses count.
  setup %{conn: conn} do
    team = team_fixture()
    %{team: team, member: member_fixture(team), conn: verify_conn(conn)}
  end

  defp verify_conn(conn) do
    conn
    |> Map.put(:host, Web.VerifyHost.host())
    |> put_req_header("fly-client-ip", "10.3.#{System.unique_integer([:positive])}")
  end

  defp check(conn, code), do: get(conn, "/api/cards/#{code}")

  test "an active card gives the member, team, qualifications, and D4H IDs", %{
    conn: conn,
    team: team,
    member: member
  } do
    qualification = qualification_fixture(team)
    endorsement = endorsement_fixture(team, %{name: "First Aid", on_card: true})
    endorsement_qualification_fixture(endorsement, qualification)
    qualification_award_fixture(qualification, member)
    card = member_card_fixture(member)
    code = MemberCard.format_code(card.code)

    body = conn |> check(code) |> json_response(200)

    assert body["status"] == "active"
    assert body["code"] == code
    assert body["sample"] == false
    assert body["member"]["name"] == member.name
    assert body["member"]["photo_url"] == Web.VerifyHost.url() <> "/#{code}/photo"
    assert [%{"name" => "First Aid"}] = body["member"]["qualifications"]
    assert body["team"]["name"] == team.name
    assert body["records"]["service"] == "d4h"
    assert body["records"]["api_url"] == "https://" <> team.d4h_api_host
    assert body["records"]["team_id"] == team.d4h_team_id
    assert body["records"]["member_id"] == member.d4h_member_id
  end

  test "a SAR Duty Records team points at Records' API", %{conn: conn} do
    team = team_fixture(%{d4h_api_host: D4H.records_host()})
    card = member_card_fixture(member_fixture(team))

    records = conn |> check(card.code) |> json_response(200) |> Map.fetch!("records")

    assert records["service"] == "records"
    assert records["api_url"] == "https://" <> D4H.records_host()
  end

  test "takes the code without its dash and in lower case", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    assert conn |> check(String.downcase(card.code)) |> json_response(200)
  end

  test "a former member's card gives the name and no photo or qualifications", %{
    conn: conn,
    team: team
  } do
    member = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    card = member_card_fixture(member)

    body = conn |> check(card.code) |> json_response(200)

    assert body["status"] == "inactive"
    assert body["member"] == %{"name" => member.name, "left_at" => "2026-01-01T00:00:00Z"}
    assert body["team"]["valid_until"] == nil
  end

  test "a cancelled card says nothing about the member", %{conn: conn, member: member} do
    card = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})

    body = conn |> check(card.code) |> json_response(200)

    assert body == %{
             "code" => MemberCard.format_code(card.code),
             "status" => "revoked",
             "sample" => false
           }
  end

  test "an unknown code is a 404", %{conn: conn} do
    assert conn |> check("ZZZZ-ZZZZ") |> json_response(404) == %{"status" => "not_found"}
    assert conn |> check("not-a-code") |> json_response(404)
  end

  test "the sample cards answer from Coast Range SAR (#854)", %{conn: conn} do
    body = conn |> check("SAMP-ACTV") |> json_response(200)
    assert body["status"] == "active"
    assert body["sample"] == true
  end

  test "misses share the page's limit", %{conn: conn} do
    for _ <- 1..20, do: check(conn, "ZZZZ-ZZZZ")

    assert conn |> check("ZZZZ-ZZZZ") |> json_response(429) == %{"status" => "limited"}
  end
end
