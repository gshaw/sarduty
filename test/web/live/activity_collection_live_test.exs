defmodule Web.ActivityCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders activities collection", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/activities")

    assert html =~ "Activities"
    assert page_title(lv) =~ "Activities"
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

    lv |> form("#activity_filter_form", form: %{when: "current"}) |> render_change()

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

    assert has_element?(lv, ~s|#activity_filter_form input[name="form[sort]"][value="date"]|)
    html = lv |> element("#activity_collection") |> render()
    assert :binary.match(html, "Next week") < :binary.match(html, "Next year")
  end

  test "the sorted column header says which way it sorts", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?sort=date")

    assert has_element?(lv, ~s|th[aria-sort="ascending"]|, "Date")
    assert lv |> element("th[aria-sort]") |> render() =~ "sort=date-"
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

  test "the kind switch counts each kind under the other filters and drops the Kind column",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    activity_fixture(team, %{
      title: "Missing hiker",
      activity_kind: "incident",
      is_published: true
    })

    activity_fixture(team, %{title: "Rope night", activity_kind: "exercise", is_published: true})
    activity_fixture(team, %{title: "Old drill", activity_kind: "exercise", is_published: false})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?status=published")

    assert has_element?(lv, "#activity-view-all[aria-current]", "2")
    assert has_element?(lv, "#activity-view-incident", "1")
    assert has_element?(lv, "#activity-view-exercise", "1")
    assert has_element?(lv, "#activity-view-event", "0")
    assert has_element?(lv, "thead th", "Kind")

    lv |> element("#activity-view-exercise") |> render_click()
    assert has_element?(lv, "#activity_collection", "Rope night")
    refute has_element?(lv, "#activity_collection", "Missing hiker")
    refute has_element?(lv, "#activity_collection", "Old drill")
    refute has_element?(lv, "thead th", "Kind")
  end

  test "Enter in the search box filters the list (#333)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, %{title: "Rope rescue night"})
    activity_fixture(team, %{title: "Board meeting"})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities")

    lv |> form("#activity_filter_form", form: %{q: "rope"}) |> render_submit()

    assert_patch(lv)
    assert has_element?(lv, "#activity_collection", "Rope rescue night")
    refute has_element?(lv, "#activity_collection", "Board meeting")
  end

  test "a filter that is on shows in blue, as a chip, and in the count", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, %{title: "Still a draft", is_published: false})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?status=draft")

    assert has_element?(lv, "#activity_filter_form .filter-menu.is-on", "Status")
    refute has_element?(lv, "#activity_filter_form .filter-menu.is-on", "Kind")
    assert has_element?(lv, "#activity_filter_form .filter-bar-count", "1")
    assert has_element?(lv, "#activity_filter_form-summary", "1 activity")

    lv |> element(".filter-bar-chips a", "Draft") |> render_click()

    assert assert_patch(lv) =~ "status=all"
    refute has_element?(lv, ".filter-bar-chips")
  end

  test "Clear shows only while a filter or search is on, and says which", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities")
    refute has_element?(lv, "#activity_filter_form-summary a", "Clear")

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?q=rope")

    lv |> element("#activity_filter_form-summary a", "Clear search") |> render_click()
    assert_patch(lv, ~p"/teams/#{team}/activities")
  end
end
