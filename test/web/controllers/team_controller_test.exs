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
end
