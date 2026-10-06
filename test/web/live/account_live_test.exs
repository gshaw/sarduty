defmodule Web.AccountLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "shows the email and links the team's settings", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/account")

    assert has_element?(lv, "#account-email", user.email)

    assert has_element?(
             lv,
             "#account-team-#{team.id}-settings[href='/teams/#{team.subdomain}/settings']"
           )

    refute html =~ "Change password"
  end

  test "a user who manages no team sees no team settings", %{conn: conn} do
    {:ok, _lv, html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")

    refute html =~ "Team settings"
  end

  test "redirects if user is not logged in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/account")
  end
end
