defmodule Web.SettingsLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "shows the email and links the team's settings", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/settings")

    assert has_element?(lv, "#settings-email", user.email)
    assert html =~ team.name
    refute html =~ "Change password"
  end

  test "a user who manages no team sees no team settings", %{conn: conn} do
    {:ok, _lv, html} = conn |> log_in_user(user_fixture()) |> live(~p"/settings")

    refute html =~ "Team settings"
  end

  test "redirects if user is not logged in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/settings")
  end
end
