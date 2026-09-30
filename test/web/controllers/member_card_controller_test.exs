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
      Plug.Conn.send_resp(conn, 200, "photo-bytes")
    end)

    conn = get(conn, ~p"/verify/#{card.code}/photo")

    assert response(conn, 200) == "photo-bytes"
  end

  test "sends the placeholder when D4H has no photo", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))

    conn = get(conn, ~p"/verify/#{card.code}/photo")

    assert response(conn, 200)
  end

  test "404s for a cancelled card without calling D4H", %{conn: conn, member: member} do
    card = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})

    conn = get(conn, ~p"/verify/#{card.code}/photo")

    assert response(conn, 404)
  end
end
