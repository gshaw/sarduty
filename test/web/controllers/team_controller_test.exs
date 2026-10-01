defmodule Web.TeamControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), team: team}
  end

  test "404s when the team has no saved logo", %{conn: conn, team: team} do
    conn = get(conn, ~p"/#{team.subdomain}/image")

    assert conn.status == 404
  end

  test "sends the saved logo", %{conn: conn, team: team} do
    team_logo_fixture(team)

    conn = get(conn, ~p"/#{team.subdomain}/image")

    assert response(conn, 200) == "png bytes"
  end

  describe "pass_logo" do
    test "sends the logo padded square, without a login", %{team: team} do
      team_logo_fixture(team, png_fixture(800, 504))

      conn = get(build_conn(), ~p"/teams/#{team.subdomain}/pass-logo")

      image = conn |> response(200) |> Image.from_binary!()
      assert {Image.width(image), Image.height(image)} == {660, 660}
    end

    test "sends SAR Duty's logo when the team has none", %{team: team} do
      conn = get(build_conn(), ~p"/teams/#{team.subdomain}/pass-logo")
      assert response(conn, 200)
    end

    test "404s for a team that doesn't exist" do
      assert build_conn() |> get(~p"/teams/no-such-team/pass-logo") |> response(404)
    end
  end
end
