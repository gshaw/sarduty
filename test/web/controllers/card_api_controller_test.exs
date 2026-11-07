defmodule Web.CardApiControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.MemberCard
  alias App.Repo

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

  defp check(conn, code), do: get(conn, "/api/v1/cards/#{code}")

  test "an active card gives the member, team, qualifications, and where the records live", %{
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

    assert body["records"] == %{
             "service" => "d4h",
             "api_url" => "https://" <> team.d4h_api_host,
             "team_id" => team.d4h_team_id,
             "member_id" => member.d4h_member_id
           }
  end

  test "times are whole seconds", %{conn: conn} do
    team = team_fixture(%{d4h_refreshed_at: ~U[2026-11-03 19:50:12.345678Z]})
    card = member_card_fixture(member_fixture(team))

    body = conn |> check(card.code) |> json_response(200)

    assert body["team"]["refreshed_at"] == "2026-11-03T19:50:12Z"
  end

  test "a SAR Duty Records team says so in the API's own name", %{conn: conn} do
    team = team_fixture(%{d4h_api_host: D4H.records_host()})
    card = member_card_fixture(member_fixture(team))

    records = conn |> check(card.code) |> json_response(200) |> Map.fetch!("records")

    assert records["service"] == "sar_duty_records"
    assert records["api_url"] == "https://" <> D4H.records_host()
  end

  test "takes the code without its dash and in lower case", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    assert conn |> check(String.downcase(card.code)) |> json_response(200)
  end

  test "a former member's card gives the name and team, and no photo, qualifications, or IDs",
       %{conn: conn, team: team} do
    member = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    card = member_card_fixture(member)

    body = conn |> check(card.code) |> json_response(200)

    assert body["status"] == "inactive"
    assert body["member"] == %{"name" => member.name, "left_at" => "2026-01-01T00:00:00Z"}
    assert body["team"]["name"] == team.name
    assert body["team"]["valid_until"] == nil
    refute Map.has_key?(body, "records")
  end

  # The same rule as logins (#514, #893): a retiring member is no longer a member.
  test "a retiring member's card is inactive, with no photo or IDs, and active once they stay",
       %{conn: conn, team: team, member: member} do
    leavers = group_fixture(team)
    team |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id) |> Repo.update!()
    membership = group_member_fixture(leavers, member)
    card = member_card_fixture(member)

    body = conn |> check(card.code) |> json_response(200)
    assert body["status"] == "inactive"
    assert body["member"] == %{"name" => member.name, "left_at" => nil}
    refute Map.has_key?(body, "records")
    assert conn |> get("/#{card.code}/photo") |> response(404)

    Repo.delete!(membership)
    assert conn |> check(card.code) |> json_response(200) |> Map.get("status") == "active"
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

  test "misses share the page's limit, and the 429 says when to try again", %{
    conn: conn,
    member: member
  } do
    card = member_card_fixture(member)
    for _ <- 1..20, do: check(conn, "ZZZZ-ZZZZ")

    conn = check(conn, card.code)

    assert json_response(conn, 429) == %{"status" => "limited"}
    assert get_resp_header(conn, "retry-after") == ["600"]
  end

  # A command post shares one IP, and an app sees every barcode there (#299).
  test "a scan that can't be a code never counts", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    for _ <- 1..25, do: assert(conn |> check("SCA-PROFILE-1234") |> json_response(404))

    assert conn |> check(card.code) |> json_response(200)
  end
end
