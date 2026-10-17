defmodule Web.ActivityLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Activity
  alias App.Operation.SetMapsApp

  test "renders activity page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity = activity_fixture(team)

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/activities/#{activity.id}")

    assert html =~ activity.title
    assert has_element?(lv, "#activity-actions")
    assert has_element?(lv, "#activity-map circle")
    refute has_element?(lv, "#deleted-in-d4h")
    assert has_element?(lv, "#activity-change-tags")
    refute has_element?(lv, "#activity-tags-in-d4h")
  end

  test "opens the latitude and longitude in maps, or the address without them", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)
    pinned = activity_fixture(team, %{title: "Rope practice"})
    unpinned = activity_fixture(team, %{coordinate: Activity.null_island()})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{pinned.id}")

    assert has_element?(
             lv,
             ~s|#activity-maps[href$="query=49.1%2C-123.1"]|,
             "Open in Google Maps"
           )

    assert has_element?(lv, ~s|#activity-copy-coordinate[value="49.1,-123.1"]|)
    assert has_element?(lv, ~s|#activity-copy-address[value="123 Main St"]|)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{unpinned.id}")
    assert has_element?(lv, ~s|#activity-maps[href$="query=123+Main+St"]|)
    refute has_element?(lv, "#activity-copy-coordinate")
  end

  test "opens places in Apple Maps for an account that chose it", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, user} = SetMapsApp.call(user, "apple")
    activity = activity_fixture(team, %{title: "Rope practice"})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities/#{activity.id}")

    assert has_element?(
             lv,
             ~s|#activity-maps[href*="ll=49.1%2C-123.1&q=Rope+practice"]|,
             "Open in Apple Maps"
           )
  end

  describe "an activity deleted in D4H" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      activity = activity_fixture(team, %{deleted_at: ~U[2026-10-05 06:00:00Z]})
      %{conn: log_in_user(conn, user), team: team, activity: activity}
    end

    test "says so and offers no actions", %{conn: conn, team: team, activity: activity} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(lv, "#deleted-in-d4h", "Deleted in D4H")
      refute has_element?(lv, "#activity-actions")
    end

    test "sends its D4H pages back to the activity", %{conn: conn, team: team, activity: activity} do
      activity_path = ~p"/teams/#{team}/activities/#{activity.id}"

      for page <- ["take-attendance", "attendance", "mileage"] do
        assert {:error, {:live_redirect, %{to: ^activity_path}}} =
                 live(conn, "#{activity_path}/#{page}")
      end
    end
  end
end
