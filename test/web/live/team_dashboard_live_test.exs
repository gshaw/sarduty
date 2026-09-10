defmodule Web.TeamDashboardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team

  test "renders team dashboard", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}")

    assert html =~ team.name
  end

  test "a failed refresh says why", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, team} =
      Team.update(team, %{
        d4h_refresh_result: "Error: No D4H key. Save a team key in Team Settings."
      })

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}")

    assert has_element?(lv, "#refresh-error", "No D4H key. Save a team key in Team Settings.")
  end
end
