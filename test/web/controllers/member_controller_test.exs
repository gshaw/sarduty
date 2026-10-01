defmodule Web.MemberControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), team: team, member: member_fixture(team)}
  end

  test "sends the member's photo cropped square", %{conn: conn, team: team, member: member} do
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))

    conn = get(conn, ~p"/#{team.subdomain}/members/#{member.id}/image")

    image = conn |> response(200) |> Image.from_binary!()
    assert {Image.width(image), Image.height(image)} == {480, 480}
  end
end
