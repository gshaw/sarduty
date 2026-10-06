defmodule Web.ActivityCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders activities collection", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}/activities")

    assert html =~ "Activities"
  end

  test "leaves out activities deleted in D4H", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    listed = activity_fixture(team, %{title: "Rope rescue night"})
    activity_fixture(team, %{title: "NO MIT Training", deleted_at: ~U[2026-10-05 06:00:00Z]})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/#{team.subdomain}/activities")

    assert has_element?(lv, "#activity_collection", listed.title)
    refute has_element?(lv, "#activity_collection", "NO MIT Training")
  end
end
