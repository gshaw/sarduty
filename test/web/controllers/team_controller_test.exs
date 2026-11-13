defmodule Web.TeamControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  setup do
    %{team: team_fixture()}
  end

  describe "logo" do
    test "sends the logo padded square, without a login", %{team: team} do
      team_logo_fixture(team, png_fixture(800, 504))

      conn = get(build_conn(), ~p"/teams/#{team}/logo")

      image = conn |> response(200) |> Image.from_binary!()
      assert {Image.width(image), Image.height(image)} == {660, 660}
    end

    test "?shape=square leaves off the circle's margin", %{team: team} do
      team_logo_fixture(team, png_fixture(800, 504))

      round = build_conn() |> get(~p"/teams/#{team}/logo") |> response(200)

      square =
        build_conn() |> get(~p"/teams/#{team}/logo?shape=square") |> response(200)

      assert square != round
    end

    test "?shape=fit keeps the logo's own shape, with no padding", %{team: team} do
      team_logo_fixture(team, png_fixture(800, 504))

      image =
        build_conn()
        |> get(~p"/teams/#{team}/logo?shape=fit")
        |> response(200)
        |> Image.from_binary!()

      assert {Image.width(image), Image.height(image)} == {480, 302}
    end

    test "sends SAR Duty's logo when the team has none", %{team: team} do
      conn = get(build_conn(), ~p"/teams/#{team}/logo")
      assert response(conn, 200)
    end

    test "404s for a team that doesn't exist" do
      assert build_conn() |> get(~p"/teams/no-such-team/logo") |> response(404)
    end

    test "caches a versioned URL for a year, and one without for 5 minutes", %{team: team} do
      versioned = get(build_conn(), ~p"/teams/#{team}/logo?v=1763028000")
      plain = get(build_conn(), ~p"/teams/#{team}/logo")

      assert get_resp_header(versioned, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]

      assert get_resp_header(plain, "cache-control") == ["public, max-age=300"]
    end
  end

  describe "logo_url/2" do
    test "carries the shape, and a version once the team has a logo", %{team: team} do
      host = Web.Endpoint.url()
      assert Web.TeamController.logo_url(team) == "#{host}/teams/#{team.subdomain}/logo"

      assert Web.TeamController.logo_url(team, :square) ==
               "#{host}/teams/#{team.subdomain}/logo?shape=square"

      team = %{team | logo_at: ~U[2025-11-13 08:00:00.000000Z]}

      assert Web.TeamController.logo_url(team, :fit) ==
               "#{host}/teams/#{team.subdomain}/logo?shape=fit&v=1763020800"

      assert Web.TeamController.logo_url(team) ==
               "#{host}/teams/#{team.subdomain}/logo?v=1763020800"
    end
  end
end
