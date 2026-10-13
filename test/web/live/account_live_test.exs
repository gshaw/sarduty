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

  test "saves the maps app place links open", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

    assert has_element?(lv, "#maps-app-google[checked]")

    lv |> form("#maps-app-form", %{maps_app: "apple"}) |> render_change()

    assert has_element?(lv, "#maps-app-apple[checked]")
    assert App.Repo.reload!(user).maps_app == "apple"

    lv |> element("#maps-app-form") |> render_change(%{maps_app: "bing"})
    assert App.Repo.reload!(user).maps_app == "apple"
  end

  test "a user who manages no team sees no team settings", %{conn: conn} do
    {:ok, _lv, html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")

    refute html =~ "Team settings"
  end

  test "redirects if user is not logged in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/account")
  end
end
