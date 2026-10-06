defmodule Web.MemberCardControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  setup do
    team = team_fixture(%{d4h_access_key: "team-key"})
    %{member: member_fixture(team)}
  end

  test "sends the member's D4H photo for a valid card", %{conn: conn, member: member} do
    card = member_card_fixture(member)

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      assert conn.request_path =~ "/members/#{member.d4h_member_id}/image"
      Plug.Conn.send_resp(conn, 200, png_fixture(640, 480))
    end)

    conn = get(conn, ~p"/verify/#{card.code}/photo")

    assert image_size(response(conn, 200)) == {480, 480}
  end

  test "sends a square placeholder when D4H's photo won't decode", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, "not an image"))

    conn = get(conn, ~p"/verify/#{card.code}/photo")

    {width, height} = image_size(response(conn, 200))
    assert width == height
  end

  test "sends the photo in the Google pass banner", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))

    conn = get(conn, ~p"/verify/#{card.code}/banner")

    assert image_size(response(conn, 200)) == {1032, 336}
  end

  test "the banner 404s for a cancelled card", %{conn: conn, member: member} do
    card = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})
    assert conn |> get(~p"/verify/#{card.code}/banner") |> response(404)
  end

  test "sends the placeholder when D4H has no photo", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))

    conn = get(conn, ~p"/verify/#{card.code}/photo")

    assert response(conn, 200)
  end

  test "404s for a member who left the team, without calling D4H", %{conn: conn} do
    team = team_fixture(%{d4h_access_key: "team-key"})
    card = member_card_fixture(member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]}))

    assert conn |> get(~p"/verify/#{card.code}/photo") |> response(404)
    assert conn |> get(~p"/verify/#{card.code}/banner") |> response(404)
  end

  test "404s for a cancelled card without calling D4H", %{conn: conn, member: member} do
    card = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})

    conn = get(conn, ~p"/verify/#{card.code}/photo")

    assert response(conn, 404)
  end

  describe "the verify limit" do
    setup %{conn: conn} do
      ip = "10.1.#{System.unique_integer([:positive])}"
      %{conn: put_req_header(conn, "fly-client-ip", ip)}
    end

    test "photo 404s count, and a limited IP is refused", %{conn: conn, member: member} do
      card = member_card_fixture(member)
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(64, 64)))

      for _ <- 1..20, do: assert(conn |> get(~p"/verify/ZZZZZZZZ/photo") |> response(404))

      assert conn |> get(~p"/verify/#{card.code}/photo") |> response(429)
      assert build_conn() |> get(~p"/verify/#{card.code}/photo") |> response(200)
    end
  end

  describe "pass" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      member = member_fixture(team)

      App.ApplePassCredentials.configure()

      %{conn: log_in_user(conn, user), team: team, member: member}
    end

    test "sends a signed pass for the member's card", %{conn: conn, team: team, member: member} do
      member_card_fixture(member)
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))

      conn = get(conn, ~p"/#{team.subdomain}/members/#{member.id}/card/pass")

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/vnd.apple.pkpass"
      {:ok, entries} = conn |> response(200) |> :zip.extract([:memory])
      files = Map.new(entries, fn {name, data} -> {to_string(name), data} end)
      assert image_size(files["thumbnail.png"]) == {480, 480}

      assert Jason.decode!(files["pass.json"])["generic"]["primaryFields"]
             |> hd()
             |> Map.get("value") ==
               member.name
    end

    test "404s when the member has no card", %{conn: conn, team: team, member: member} do
      conn = get(conn, ~p"/#{team.subdomain}/members/#{member.id}/card/pass")
      assert response(conn, 404)
    end

    test "404s when passes aren't set up", %{conn: conn, team: team, member: member} do
      member_card_fixture(member)
      Application.put_env(:sarduty, :apple_pass, [])

      conn = get(conn, ~p"/#{team.subdomain}/members/#{member.id}/card/pass")
      assert response(conn, 404)
    end
  end

  describe "google_pass" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      member = member_fixture(team)

      App.GoogleWalletCredentials.configure()
      App.GoogleWalletCredentials.stub(self())

      %{conn: log_in_user(conn, user), team: team, member: member}
    end

    test "sends the pass to Google and opens its save page",
         %{conn: conn, team: team, member: member} do
      member_card_fixture(member)

      conn = get(conn, ~p"/#{team.subdomain}/members/#{member.id}/card/google-pass")

      assert redirected_to(conn) =~ "https://pay.google.com/gp/v/save/"
      assert_received {:google, "PUT", "/walletobjects/v1/genericObject/" <> _, _object}
    end

    test "404s when the member has no card", %{conn: conn, team: team, member: member} do
      conn = get(conn, ~p"/#{team.subdomain}/members/#{member.id}/card/google-pass")
      assert response(conn, 404)
    end

    test "404s when Google Wallet isn't set up", %{conn: conn, team: team, member: member} do
      member_card_fixture(member)
      Application.put_env(:sarduty, :google_wallet, [])

      conn = get(conn, ~p"/#{team.subdomain}/members/#{member.id}/card/google-pass")
      assert response(conn, 404)
    end
  end

  defp image_size(png) do
    image = Image.from_binary!(png)
    {Image.width(image), Image.height(image)}
  end
end
