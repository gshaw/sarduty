defmodule Web.ActivityCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders activities collection", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/activities")

    assert html =~ "Activities"
  end

  test "leaves out activities deleted in D4H", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    listed = activity_fixture(team, %{title: "Rope rescue night"})
    activity_fixture(team, %{title: "NO MIT Training", deleted_at: ~U[2026-10-05 06:00:00Z]})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities")

    assert has_element?(lv, "#activity_collection", listed.title)
    refute has_element?(lv, "#activity_collection", "NO MIT Training")
  end

  test "Current shows a week either side of today, oldest first", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    days = fn n -> DateTime.add(now, n * 86_400, :second) end

    activity_fixture(team, %{
      title: "Rope rescue night",
      started_at: days.(-3),
      finished_at: days.(-3)
    })

    activity_fixture(team, %{title: "Board meeting", started_at: days.(4), finished_at: days.(4)})

    activity_fixture(team, %{
      title: "Rope tech weekend",
      started_at: days.(-10),
      finished_at: days.(1)
    })

    activity_fixture(team, %{title: "Old search", started_at: days.(-30), finished_at: days.(-30)})

    activity_fixture(team, %{title: "Next year", started_at: days.(300), finished_at: days.(300)})

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities")

    {:ok, lv, _html} =
      lv |> element("#activities_current_link") |> render_click() |> follow_redirect(conn)

    assert has_element?(lv, "#activity_collection", "Rope rescue night")
    assert has_element?(lv, "#activity_collection", "Board meeting")
    assert has_element?(lv, "#activity_collection", "Rope tech weekend")
    refute has_element?(lv, "#activity_collection", "Old search")
    refute has_element?(lv, "#activity_collection", "Next year")

    html = lv |> element("#activity_collection") |> render()
    assert :binary.match(html, "Rope rescue night") < :binary.match(html, "Board meeting")
  end

  test "picking Future from the menu sorts it oldest first", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    days = fn n -> DateTime.add(now, n * 86_400, :second) end
    activity_fixture(team, %{title: "Next week", started_at: days.(7), finished_at: days.(7)})
    activity_fixture(team, %{title: "Next year", started_at: days.(300), finished_at: days.(300)})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?when=past&sort=date-")

    lv |> form("#activity_filter_form", form: %{when: "future"}) |> render_change()

    assert has_element?(lv, ~s|#activity_filter_form option[value="date"][selected]|)
    html = lv |> element("#activity_collection") |> render()
    assert :binary.match(html, "Next week") < :binary.match(html, "Next year")
  end

  test "the draft filter lists only activities D4H hasn't published", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, %{title: "Still a draft", is_published: false})
    activity_fixture(team, %{title: "Already published", is_published: true})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/activities?status=draft")

    assert has_element?(lv, "#activity_collection", "Still a draft")
    refute has_element?(lv, "#activity_collection", "Already published")
  end
end
