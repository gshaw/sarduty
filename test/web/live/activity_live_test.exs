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

  describe "for a member" do
    setup %{conn: conn} do
      %{team: team, member: member, user: user} = member_with_login_fixture()
      %{conn: log_in_user(conn, user), team: team, member: member}
    end

    defp hours_from_now(hours),
      do: DateTime.utc_now() |> DateTime.add(hours, :hour) |> DateTime.truncate(:second)

    test "a past activity: its facts and who attended, names only, and no actions",
         %{conn: conn, team: team, member: member} do
      started = hours_from_now(-30)
      activity = activity_fixture(team, %{title: "Rope practice", started_at: started})
      attendance_fixture(activity, member, %{started_at: started})
      other = member_fixture(team, %{name: "Casey Dhillon"})
      attendance_fixture(activity, other, %{started_at: started})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(lv, "h1", "Rope practice")
      assert has_element?(lv, "#activity-people h2", "Attended · 2")
      assert has_element?(lv, "#activity-names", "Casey Dhillon")
      refute has_element?(lv, "#activity-names a")
      assert has_element?(lv, "#activity-map circle")

      assert has_element?(
               lv,
               ~s{#activity-calendar[href="/teams/#{team.subdomain}/activities/#{activity.id}/calendar"]}
             )

      refute has_element?(lv, "#activity-actions")
      refute has_element?(lv, "#activity-history-link")
      refute has_element?(lv, "#activity-equipment")
      refute has_element?(lv, ".tag")
    end

    test "a coming activity lists who signed up", %{conn: conn, team: team, member: member} do
      starts = hours_from_now(48)
      activity = activity_fixture(team, %{started_at: starts})
      attendance_fixture(activity, member, %{started_at: starts})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
      assert has_element?(lv, "#activity-people h2", "Signed up · 1")
      assert has_element?(lv, "#activity-names", member.name)
    end

    test "an incident the member did not attend, or a deleted activity, is a 404",
         %{conn: conn, team: team, member: member} do
      started = hours_from_now(-30)
      incident = activity_fixture(team, %{activity_kind: "incident", started_at: started})
      deleted = activity_fixture(team, %{deleted_at: started})

      for activity <- [incident, deleted] do
        assert_raise Ecto.NoResultsError, fn ->
          live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
        end

        assert_error_sent 404, fn ->
          get(conn, ~p"/teams/#{team}/activities/#{activity.id}/calendar")
        end
      end

      attendance_fixture(incident, member, %{started_at: started})
      {:ok, _lv, html} = live(conn, ~p"/teams/#{team}/activities/#{incident.id}")
      assert html =~ incident.title
    end

    test "Add to calendar is an .ics file of the activity", %{conn: conn, team: team} do
      activity = activity_fixture(team, %{title: "Rope practice", started_at: hours_from_now(48)})
      conn = get(conn, ~p"/teams/#{team}/activities/#{activity.id}/calendar")

      assert response(conn, 200) =~ "SUMMARY:Rope practice"
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "text/calendar"
    end

    test "the list opens on coming activities, with no tags, hours, or team admin tools",
         %{conn: conn, team: team} do
      activity_fixture(team, %{title: "Swiftwater course", started_at: hours_from_now(48)})
      activity_fixture(team, %{title: "Last week course", started_at: hours_from_now(-170)})

      activity_fixture(team, %{
        title: "Missing hiker",
        activity_kind: "incident",
        started_at: hours_from_now(1)
      })

      {:ok, lv, html} = live(conn, ~p"/teams/#{team}/activities")

      assert has_element?(lv, "#activity_collection", "Swiftwater course")
      refute html =~ "Last week course"
      refute html =~ "Missing hiker"
      refute has_element?(lv, ".tabs")
      refute has_element?(lv, "#activity-add")
      refute has_element?(lv, "#activity_collection .tag")
      refute has_element?(lv, "#activity_collection", "Draft")
      refute has_element?(lv, "#activity_filter_form-summary", "Clear filters")
      refute has_element?(lv, "select[name='form[status]']")
      refute has_element?(lv, "select[name='form[hours]']")
      assert has_element?(lv, "#side-nav-activities[aria-current=page]")

      {:ok, _lv, html} = live(conn, ~p"/teams/#{team}/activities?when=all")
      assert html =~ "Last week course"
      refute html =~ "Missing hiker"
    end
  end
end
