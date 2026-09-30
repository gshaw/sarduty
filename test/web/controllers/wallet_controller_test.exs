defmodule Web.WalletControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Repo

  @pass_type "pass.com.sarduty.member-card"

  setup do
    App.ApplePassCredentials.configure()
    team = team_fixture()
    member = member_fixture(team)

    card =
      member_card_fixture(member, %{
        authentication_token: "token-0123456789abcdef",
        pass_updated_at: ~U[2026-09-30 12:00:00.000000Z]
      })

    %{card: card, serial: MemberCard.serial_number(card)}
  end

  defp authed(conn, token \\ "token-0123456789abcdef"),
    do: put_req_header(conn, "authorization", "ApplePass #{token}")

  defp register(conn, serial, device \\ "device-1") do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/wallet/v1/devices/#{device}/registrations/#{@pass_type}/#{serial}", %{
      pushToken: "push-token-1"
    })
  end

  test "registers a phone once, then says it already is", %{
    conn: conn,
    card: card,
    serial: serial
  } do
    assert conn |> authed() |> register(serial) |> response(201)
    assert build_conn() |> authed() |> register(serial) |> response(200)
    assert [%{push_token: "push-token-1"}] = PassRegistration.get_all_for_card(card)
  end

  test "refuses a wrong token, a missing one, or another pass type", %{conn: conn, serial: serial} do
    assert conn |> authed("wrong") |> register(serial) |> response(401)
    assert build_conn() |> register(serial) |> response(401)

    assert build_conn()
           |> authed()
           |> post("/wallet/v1/devices/d/registrations/pass.other/#{serial}", %{pushToken: "t"})
           |> response(401)
  end

  test "unregisters a phone", %{conn: conn, card: card, serial: serial} do
    build_conn() |> authed() |> register(serial)

    conn =
      conn
      |> authed()
      |> delete("/wallet/v1/devices/device-1/registrations/#{@pass_type}/#{serial}")

    assert response(conn, 200)
    assert PassRegistration.get_all_for_card(card) == []
  end

  test "lists the phone's passes changed since its last tag", %{
    conn: conn,
    card: card,
    serial: serial
  } do
    build_conn() |> authed() |> register(serial)

    conn = get(conn, "/wallet/v1/devices/device-1/registrations/#{@pass_type}")
    assert %{"serialNumbers" => [^serial], "lastUpdated" => tag} = json_response(conn, 200)

    conn =
      get(
        build_conn(),
        "/wallet/v1/devices/device-1/registrations/#{@pass_type}?passesUpdatedSince=#{tag}"
      )

    assert response(conn, 204)

    card
    |> Ecto.Changeset.change(pass_updated_at: ~U[2026-10-01 12:00:00.000000Z])
    |> Repo.update!()

    conn =
      get(
        build_conn(),
        "/wallet/v1/devices/device-1/registrations/#{@pass_type}?passesUpdatedSince=#{tag}"
      )

    assert %{"serialNumbers" => [^serial]} = json_response(conn, 200)
  end

  test "another phone sees none of this phone's passes", %{conn: conn, serial: serial} do
    build_conn() |> authed() |> register(serial)
    conn = get(conn, "/wallet/v1/devices/device-2/registrations/#{@pass_type}")
    assert response(conn, 204)
  end

  test "sends the latest pass, voided once the card is cancelled", %{
    conn: conn,
    card: card,
    serial: serial
  } do
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))
    card |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()

    conn = conn |> authed() |> get("/wallet/v1/passes/#{@pass_type}/#{serial}")

    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "application/vnd.apple.pkpass"
    {:ok, entries} = conn |> response(200) |> :zip.extract([:memory])

    json =
      entries
      |> Map.new(fn {n, d} -> {to_string(n), d} end)
      |> Map.fetch!("pass.json")
      |> Jason.decode!()

    assert json["voided"] == true
    assert json["authenticationToken"] == "token-0123456789abcdef"
  end

  test "won't send a pass without the token", %{conn: conn, serial: serial} do
    assert conn |> get("/wallet/v1/passes/#{@pass_type}/#{serial}") |> response(401)
  end

  test "accepts Wallet's log messages", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/wallet/v1/log", %{logs: ["something went wrong"]})

    assert response(conn, 200)
  end
end
