defmodule Web.Settings.TeamLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders team settings when team exists", %{conn: conn} do
    %{user: user} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/settings/team")

    assert html =~ "Team settings"
  end
end
