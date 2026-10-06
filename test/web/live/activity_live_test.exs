defmodule Web.ActivityLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders activity page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity = activity_fixture(team)

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}/activities/#{activity.id}")

    assert html =~ activity.title
    assert has_element?(lv, "#activity-actions")
    refute has_element?(lv, "#deleted-in-d4h")
  end

  describe "an activity deleted in D4H" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      activity = activity_fixture(team, %{deleted_at: ~U[2026-10-05 06:00:00Z]})
      %{conn: log_in_user(conn, user), team: team, activity: activity}
    end

    test "says so and offers no actions", %{conn: conn, team: team, activity: activity} do
      {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/activities/#{activity.id}")

      assert has_element?(lv, "#deleted-in-d4h", "Deleted in D4H")
      refute has_element?(lv, "#activity-actions")
    end

    test "sends its D4H pages back to the activity", %{conn: conn, team: team, activity: activity} do
      activity_path = ~p"/#{team.subdomain}/activities/#{activity.id}"

      for page <- ["take-attendance", "attendance", "mileage"] do
        assert {:error, {:live_redirect, %{to: ^activity_path}}} =
                 live(conn, "#{activity_path}/#{page}")
      end
    end
  end
end
