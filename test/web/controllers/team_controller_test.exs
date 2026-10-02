defmodule Web.TeamControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  setup do
    %{team: team_fixture()}
  end

  describe "logo" do
    test "sends the logo padded square, without a login", %{team: team} do
      team_logo_fixture(team, png_fixture(800, 504))

      conn = get(build_conn(), ~p"/teams/#{team.subdomain}/logo")

      image = conn |> response(200) |> Image.from_binary!()
      assert {Image.width(image), Image.height(image)} == {660, 660}
    end

    test "?shape=square leaves off the circle's margin", %{team: team} do
      team_logo_fixture(team, png_fixture(800, 504))

      round = build_conn() |> get(~p"/teams/#{team.subdomain}/logo") |> response(200)

      square =
        build_conn() |> get(~p"/teams/#{team.subdomain}/logo?shape=square") |> response(200)

      assert square != round
    end

    test "sends SAR Duty's logo when the team has none", %{team: team} do
      conn = get(build_conn(), ~p"/teams/#{team.subdomain}/logo")
      assert response(conn, 200)
    end

    test "404s for a team that doesn't exist" do
      assert build_conn() |> get(~p"/teams/no-such-team/logo") |> response(404)
    end
  end
end
