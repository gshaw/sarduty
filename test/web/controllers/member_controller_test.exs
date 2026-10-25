defmodule Web.MemberControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), team: team, member: member_fixture(team)}
  end

  test "sends the member's photo cropped square", %{conn: conn, team: team, member: member} do
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))

    conn = get(conn, ~p"/teams/#{team}/members/#{member.id}/image")

    image = conn |> response(200) |> Image.from_binary!()
    assert {Image.width(image), Image.height(image)} == {480, 480}
  end

  test "sends a member's certificate", %{conn: conn, team: team, member: member} do
    award = certificate_award_fixture(team, member)

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      assert conn.request_path =~ "/documents/77/download"

      conn
      |> Plug.Conn.put_resp_content_type("image/jpeg", nil)
      |> Plug.Conn.send_resp(200, "jpeg")
    end)

    conn = get(conn, ~p"/teams/#{team}/members/#{member.id}/certificates/#{award.id}")
    assert response(conn, 200) == "jpeg"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(inline; filename="Standard First Aid.jpg")
           ]
  end

  test "another member's certificate is a 404", %{conn: conn, team: team, member: member} do
    award = certificate_award_fixture(team, member_fixture(team))

    assert_error_sent 404, fn ->
      get(conn, ~p"/teams/#{team}/members/#{member.id}/certificates/#{award.id}")
    end
  end

  test "answers 404 when D4H has no photo, so the header shows initials",
       %{conn: conn, team: team, member: member} do
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))

    assert conn |> get(~p"/teams/#{team}/members/#{member.id}/image") |> response(404)
  end

  describe "for a member (#440)" do
    setup %{conn: conn} do
      %{team: team, user: user} = member_with_login_fixture()
      %{conn: log_in_user(conn, user), team: team, other: member_fixture(team)}
    end

    test "sends another member's photo, for their page's header",
         %{conn: conn, team: team, other: other} do
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))
      assert conn |> get(~p"/teams/#{team}/members/#{other.id}/image") |> response(200)
    end

    test "a certificate stays a 404: D4H marks them RESTRICTED",
         %{conn: conn, team: team, other: other} do
      award = certificate_award_fixture(team, other)

      assert_error_sent 404, fn ->
        get(conn, ~p"/teams/#{team}/members/#{other.id}/certificates/#{award.id}")
      end
    end
  end
end
