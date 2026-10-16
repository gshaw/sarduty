defmodule Web.GroupCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "search finds groups by name (#350)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    rope = group_fixture(team, %{title: "Rope rescue"})
    drivers = group_fixture(team, %{title: "Drivers"})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/groups")

    lv |> form("#group_filter_form", form: %{q: "ROPE"}) |> render_change()

    assert has_element?(lv, "#group-#{rope.id}")
    refute has_element?(lv, "#group-#{drivers.id}")
    assert has_element?(lv, "#group_filter_form-summary", "1 group")

    lv |> form("#group_filter_form", form: %{q: "nothing"}) |> render_change()
    assert has_element?(lv, "#no-matching-groups")
  end
end
