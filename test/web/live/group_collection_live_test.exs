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

  test "tiles split the groups by owner, and Out of step keeps those with changes (#652)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    organization_fixture([team], %{short_name: "BCSARA"})
    aircraft = group_fixture(team, %{title: "Aircraft", organization_owned: true})
    callout = group_fixture(team, %{title: "Callout"})
    gsar = group_fixture(team, %{title: "GSAR"})
    group_rule_fixture(callout, gsar)
    group_member_fixture(callout, member_fixture(team))

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/groups")
    assert has_element?(lv, "#group-#{aircraft.id}", "Aircraft · BCSARA")

    lv |> element("#groups-organization-link") |> render_click()
    assert_patch(lv, ~p"/teams/#{team}/groups?view=organization")
    assert has_element?(lv, "#group-#{aircraft.id}")
    refute has_element?(lv, "#group-#{aircraft.id}", "BCSARA")
    refute has_element?(lv, "#group-#{callout.id}")

    lv |> element("#groups-team-link") |> render_click()
    refute has_element?(lv, "#group-#{aircraft.id}")
    assert has_element?(lv, "#group-#{callout.id}")
    assert has_element?(lv, "#group-#{gsar.id}")

    lv |> element("#groups-out-of-step-link") |> render_click()
    assert has_element?(lv, "#groups-out-of-step-link", "1")
    assert has_element?(lv, "#group-#{callout.id}")
    refute has_element?(lv, "#group-#{gsar.id}")
    refute has_element?(lv, "#group-#{aircraft.id}")
  end

  test "a team without an organization has no owner tiles, and an unknown view is not found",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    group_fixture(team, %{title: "Drivers"})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/groups")
    assert has_element?(lv, "#groups-all-link")
    refute has_element?(lv, "#groups-organization-link")
    refute has_element?(lv, "#groups-team-link")

    lv |> element("#groups-out-of-step-link") |> render_click()
    assert has_element?(lv, "#no-out-of-step-groups")

    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/groups?view=other") end
  end
end
