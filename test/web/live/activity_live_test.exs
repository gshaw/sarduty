defmodule Web.ActivityLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AttendanceStub
  alias App.Model.Activity
  alias App.Operation.SetMapsApp
  alias App.Repo

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
    refute has_element?(lv, "#activity-tags-locked")
  end

  test "a chore activity's kind is Chores (#575)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity = chore_activity_fixture(team, [60])

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities/#{activity.id}")

    assert has_element?(lv, ".badge-chores", "Chores")
    refute has_element?(lv, ".badge-event")
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

  test "Take attendance is under the title for a team admin, and Send attendance in Actions",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity = activity_fixture(team)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities/#{activity.id}")

    assert has_element?(
             lv,
             ~s{#activity-panel-take-attendance[href="/teams/#{team.subdomain}/activities/#{activity.id}/take-attendance"]}
           )

    refute has_element?(lv, "#activity-actions", "Take attendance")

    assert has_element?(
             lv,
             ~s{#activity-send-attendance[href="/teams/#{team.subdomain}/activities/#{activity.id}/attendance"]}
           )
  end

  test "a team admin who is a member replies too, with member logins off", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = Repo.get_by!(App.Model.Member, team_id: team.id, email: user.email)
    activity = activity_fixture(team, %{started_at: hours_from_now(48)})
    attendance_fixture(activity, member, %{status: "requested"})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities/#{activity.id}")

    assert has_element?(lv, "#activity-reply-yes", "I'll be there")
    assert has_element?(lv, "#activity-panel-take-attendance")
  end

  describe "reminders (#444)" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      App.Model.Member
      |> Repo.get_by!(team_id: team.id, email: user.email)
      |> Ecto.Changeset.change(name: "Alex Chen")
      |> Repo.update!()

      activity = activity_fixture(team, %{started_at: hours_from_now(72)})
      cameron = member_fixture(team, %{name: "Cameron Ruiz"})
      frankie = member_fixture(team, %{name: "Frankie Moore"})
      wren = member_fixture(team, %{name: "Wren Adams", email: nil})

      for m <- [cameron, frankie, wren],
          do: attendance_fixture(activity, m, %{status: "requested"})

      %{
        conn: log_in_user(conn, user),
        team: team,
        activity: activity,
        cameron: cameron,
        wren: wren
      }
    end

    test "Email members opens its own page, and the batch note shows what went (#608)",
         %{conn: conn, team: team, activity: activity, cameron: cameron, wren: wren} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(
               lv,
               ~s{#activity-email-members[href="/teams/#{team.subdomain}/activities/#{activity.id}/email"]},
               "Email members"
             )

      {:ok, lv, _html} =
        lv |> element("#activity-email-members") |> render_click() |> follow_redirect(conn)

      {:ok, lv, _html} =
        lv |> form("#email-form") |> render_submit() |> follow_redirect(conn)

      assert_received {:email, %{to: [{"Cameron Ruiz", _}]}}
      assert_received {:email, %{to: [{"Frankie Moore", _}]}}
      refute_received {:email, _}
      assert has_element?(lv, "#members-batch", "2 sent")
      assert has_element?(lv, "#members-batch", "by Alex Chen · 0 replied since")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}?view=no-reply")
      assert has_element?(lv, "#activity-members th", "Replied")
      assert has_element?(lv, "#member-reminded-#{cameron.id}", "Reminded ")
      refute has_element?(lv, "#member-reminded-#{wren.id}")
      refute has_element?(lv, "#member-row-#{cameron.id} td", "No reply ·")
    end

    test "a reminder waiting for its job shows as sending until the job is done",
         %{conn: conn, team: team, activity: activity, cameron: cameron} do
      reminder =
        Repo.insert!(%App.Model.Reminder{
          team_id: team.id,
          activity_id: activity.id,
          member_id: cameron.id,
          sent_at: DateTime.utc_now(),
          status: :queued
        })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}?view=no-reply")
      assert has_element?(lv, "#members-batch", "1 sending")
      assert has_element?(lv, "#member-reminded-#{cameron.id}", "Reminder sending")

      reminder |> Ecto.Changeset.change(status: :sent) |> Repo.update!()
      send(lv.pid, {:reminder_done, activity.id})

      assert has_element?(lv, "#members-batch", "1 sent")
      assert has_element?(lv, "#member-reminded-#{cameron.id}", "Reminded ")
    end
  end

  describe "Add members (#564)" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      %{conn: log_in_user(conn, user), team: team}
    end

    test "beside Members before the start, with nobody on it yet", %{conn: conn, team: team} do
      activity = activity_fixture(team, %{started_at: hours_from_now(48)})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(
               lv,
               ~s{#activity-members .action #members-add[href="/teams/#{team.subdomain}/activities/#{activity.id}/members"]},
               "Add members"
             )

      assert has_element?(lv, "#members-empty", "Nobody has signed up yet.")
    end

    test "gone once the activity starts", %{conn: conn, team: team} do
      activity = activity_fixture(team, %{started_at: hours_from_now(-1)})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
      refute has_element?(lv, "#members-add")
      refute has_element?(lv, "#members-published")
    end

    test "a published activity says why instead", %{conn: conn, team: team} do
      activity = activity_fixture(team, %{started_at: hours_from_now(48), is_published: true})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      refute has_element?(lv, "#members-add")

      assert has_element?(
               lv,
               "#members-published",
               "Published, so nobody can be added. Unpublish it with Change activity first."
             )
    end
  end

  defp hours_from_now(hours),
    do: DateTime.utc_now() |> DateTime.add(hours, :hour) |> DateTime.truncate(:second)

  defp row_ids(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#members-table tr")
    |> Enum.flat_map(&Floki.attribute(&1, "id"))
  end

  describe "an activity deleted in D4H" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      activity = activity_fixture(team, %{deleted_at: ~U[2026-10-05 06:00:00Z]})
      %{conn: log_in_user(conn, user), team: team, activity: activity}
    end

    test "says so and offers no actions", %{conn: conn, team: team, activity: activity} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(lv, "#deleted-in-d4h", "Deleted")
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

    test "a past activity: the facts and people a team admin sees, without the actions",
         %{conn: conn, team: team, member: member} do
      started = hours_from_now(-30)

      activity =
        activity_fixture(team, %{
          title: "Rope practice",
          started_at: started,
          tags: ["Primary Hours", "Rope"]
        })

      attendance_fixture(activity, member, %{started_at: started})
      other = member_fixture(team, %{name: "Casey Dhillon"})
      attendance_fixture(activity, other, %{started_at: started, duration_in_minutes: 90})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(lv, "h1", "Rope practice")
      assert has_element?(lv, "#members-view-attended", "2")
      assert has_element?(lv, "#members-table", "Casey Dhillon")
      assert has_element?(lv, "#members-table", "1h 30m")
      refute has_element?(lv, "#members-table th", "ID")
      refute has_element?(lv, "#members-table", other.ref_id)

      assert has_element?(
               lv,
               ~s{#member-row-#{other.id} a[href^="/teams/#{team.subdomain}/members/#{other.id}"]}
             )

      assert has_element?(lv, "#activity-map circle")
      assert has_element?(lv, ".badge", "Rope")
      assert has_element?(lv, "dt", "Tax credit hours")
      assert has_element?(lv, "#activity-equipment")

      assert has_element?(
               lv,
               ~s{#activity-calendar[href="/teams/#{team.subdomain}/activities/#{activity.id}/calendar"]}
             )

      refute has_element?(lv, "#activity-actions")
      refute has_element?(lv, "#activity-history-link")
      refute has_element?(lv, "#activity-equipment-add")
    end

    test "Take attendance shows from 2 hours before the start", %{conn: conn, team: team} do
      later =
        activity_fixture(team, %{started_at: hours_from_now(3), finished_at: hours_from_now(4)})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{later.id}")
      refute has_element?(lv, "#activity-panel-take-attendance")

      soon =
        activity_fixture(team, %{started_at: hours_from_now(1), finished_at: hours_from_now(2)})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{soon.id}")
      assert has_element?(lv, "#activity-panel-take-attendance")
    end

    test "a coming activity lists who signed up", %{conn: conn, team: team, member: member} do
      starts = hours_from_now(48)
      activity = activity_fixture(team, %{started_at: starts})
      attendance_fixture(activity, member, %{started_at: starts})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
      assert has_element?(lv, "#member-row-#{member.id}", "Signed up")
      refute has_element?(lv, "#members-add")
    end

    test "an invited member replies under the title; Change brings the buttons back",
         %{conn: conn, team: team, member: member} do
      team = team |> Ecto.Changeset.change(d4h_access_key: "team-key") |> Repo.update!()
      starts = hours_from_now(48)

      activity =
        activity_fixture(team, %{started_at: starts, finished_at: DateTime.add(starts, 3, :hour)})

      row = attendance_fixture(activity, member, %{status: "requested"})
      attendance_fixture(activity, member_fixture(team), %{status: "absent"})
      AttendanceStub.stub([row])

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(
               lv,
               "#activity-panel-counts",
               "0 signed up · 1 can't make it · 1 no reply"
             )

      refute has_element?(lv, "#activity-panel-take-attendance")

      lv |> element("#activity-reply-yes") |> render_click()

      assert_received {:d4h_write, _id, %{"status" => "ATTENDING"}}
      assert has_element?(lv, "#activity-reply-state", "Signed up")
      assert has_element?(lv, "#activity-panel-counts", "1 signed up · 1 can't make it")
      assert has_element?(lv, "#member-row-#{member.id} .marker-signed-up", "Signed up")
      refute has_element?(lv, "#activity-reply-yes")

      assert has_element?(
               lv,
               ~s{#activity-reply-calendar[href="/teams/#{team.subdomain}/activities/#{activity.id}/calendar"]},
               "Add to calendar"
             )

      lv |> element("#activity-reply-change") |> render_click()
      lv |> element("#activity-reply-no") |> render_click()

      assert_received {:d4h_write, _id, %{"status" => "ABSENT"}}
      assert has_element?(lv, "#activity-reply-state", "Can't make it")
      refute has_element?(lv, "#activity-reply-calendar")
      assert has_element?(lv, "#activity-panel-counts", "0 signed up · 2 can't make it")
    end

    test "a member sees who was reminded, but no button", %{conn: conn, team: team} do
      activity = activity_fixture(team, %{started_at: hours_from_now(48)})
      other = member_fixture(team)
      attendance_fixture(activity, other, %{status: "requested"})

      Repo.insert!(%App.Model.Reminder{
        team_id: team.id,
        activity_id: activity.id,
        member_id: other.id,
        sent_at: DateTime.utc_now(),
        status: :failed
      })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(lv, "#members-batch", "0 sent")
      assert has_element?(lv, "#member-reminded-#{other.id}", "Reminder failed")
      refute has_element?(lv, "#activity-email-members")
    end

    test "a member who isn't invited sees the counts alone", %{conn: conn, team: team} do
      activity = activity_fixture(team, %{started_at: hours_from_now(48)})
      attendance_fixture(activity, member_fixture(team), %{status: "requested"})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(lv, "#activity-panel-counts", "0 signed up · 1 no reply")
      refute has_element?(lv, "#activity-reply")
    end

    test "replies close at the start, and the counts use D4H's words",
         %{conn: conn, team: team, member: member} do
      started = hours_from_now(-1)
      activity = activity_fixture(team, %{started_at: started})
      attendance_fixture(activity, member, %{status: "requested", started_at: started})
      attendance_fixture(activity, member_fixture(team), %{started_at: started})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(lv, "#activity-panel-counts", "1 attended · 1 no reply")
      refute has_element?(lv, "#activity-reply")
    end

    test "Members: counts that filter one table, by reply then name",
         %{conn: conn, team: team, member: member} do
      activity = activity_fixture(team, %{started_at: hours_from_now(48)})
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      quinn = member_fixture(team, %{name: "Quinn Laval"})
      avery = member_fixture(team, %{name: "Avery Chen"})
      wren = member_fixture(team, %{name: "Wren Adams"})

      attendance_fixture(activity, quinn, %{
        status: "absent",
        replied_at: DateTime.add(now, -3, :day)
      })

      attendance_fixture(activity, avery, %{
        status: "attending",
        replied_at: DateTime.add(now, -2, :hour)
      })

      attendance_fixture(activity, member, %{
        status: "attending",
        replied_at: DateTime.add(now, -2, :day)
      })

      attendance_fixture(activity, wren, %{status: "requested"})
      # D4H allows a second row for one member; the one with a reply shows (#519).
      attendance_fixture(activity, member, %{status: "requested"})

      {:ok, lv, html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert row_ids(html) == Enum.map([avery, member, quinn, wren], &"member-row-#{&1.id}")
      assert has_element?(lv, "#members-view-all", "4")
      assert has_element?(lv, "#members-view-signed-up", "2")
      assert has_element?(lv, "#members-view-cant-make-it .marker-cant-make-it", "Can't make it")
      assert has_element?(lv, "#member-row-#{wren.id} .marker-no-reply", "No reply")
      assert has_element?(lv, "#activity-members th", "Reply")
      assert has_element?(lv, "#member-row-#{avery.id} .badge-primary", "New")
      refute has_element?(lv, "#member-row-#{member.id} .badge", "New")
      refute has_element?(lv, "#members-heading", "·")

      {:ok, lv, html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}?view=signed-up")
      assert row_ids(html) == Enum.map([avery, member], &"member-row-#{&1.id}")
      assert has_element?(lv, "#members-view-signed-up[aria-current=page]")
      assert has_element?(lv, "#activity-members th", "Reply")
      assert has_element?(lv, "#activity-members th", "Replied")

      {:ok, lv, html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}?view=no-reply")
      assert row_ids(html) == ["member-row-#{wren.id}"]
      refute has_element?(lv, "#activity-members th", "Replied")
    end

    test "Members once it starts: D4H's words and each member's times",
         %{conn: conn, team: team, member: member} do
      started = hours_from_now(-3)

      activity =
        activity_fixture(team, %{
          started_at: started,
          finished_at: DateTime.add(started, 3, :hour)
        })

      late = member_fixture(team, %{name: "Morgan Singh"})
      away = member_fixture(team, %{name: "Quinn Laval"})
      attendance_fixture(activity, member, %{started_at: started})
      attendance_fixture(activity, late, %{started_at: DateTime.add(started, 1, :day)})
      attendance_fixture(activity, away, %{status: "absent"})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")

      assert has_element?(lv, "#members-view-attended", "2")
      assert has_element?(lv, "#members-view-absent", "Absent")
      assert has_element?(lv, "#activity-members th", "Attendance")
      refute has_element?(lv, "#activity-members th", "Replied")
      assert has_element?(lv, "#member-row-#{member.id} .marker-signed-up", "Attended")

      start = Service.Format.time_short(started, team.timezone)
      assert has_element?(lv, "#member-row-#{member.id} td", start)

      next_day = DateTime.add(started, 1, :day)

      assert has_element?(
               lv,
               "#member-row-#{late.id} td",
               Service.Format.month_day_time(next_day, team.timezone)
             )

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}?view=absent")
      refute has_element?(lv, "#activity-members th", "Start")
      assert has_element?(lv, "#member-row-#{away.id}")
    end

    test "every activity D4H has, incidents too; a deleted one is a 404",
         %{conn: conn, team: team} do
      started = hours_from_now(-30)

      incident =
        activity_fixture(team, %{
          title: "Missing hiker",
          activity_kind: "incident",
          started_at: started
        })

      {:ok, _lv, html} = live(conn, ~p"/teams/#{team}/activities/#{incident.id}")
      assert html =~ "Missing hiker"

      deleted = activity_fixture(team, %{deleted_at: started})

      assert_raise Web.Status.NotFound, fn ->
        live(conn, ~p"/teams/#{team}/activities/#{deleted.id}")
      end

      assert_error_sent 404, fn ->
        get(conn, ~p"/teams/#{team}/activities/#{deleted.id}/calendar")
      end
    end

    test "Add to calendar is an .ics file of the activity", %{conn: conn, team: team} do
      activity = activity_fixture(team, %{title: "Rope practice", started_at: hours_from_now(48)})
      conn = get(conn, ~p"/teams/#{team}/activities/#{activity.id}/calendar")

      assert response(conn, 200) =~ "SUMMARY:Rope practice"
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "text/calendar"
    end

    test "the list is the team admin's, without Add activity or the tabs",
         %{conn: conn, team: team} do
      activity_fixture(team, %{title: "Swiftwater course", started_at: hours_from_now(48)})
      activity_fixture(team, %{title: "Last week course", started_at: hours_from_now(-170)})

      activity_fixture(team, %{
        title: "Missing hiker",
        activity_kind: "incident",
        started_at: hours_from_now(-20),
        tags: ["Primary Hours", "Rope"]
      })

      {:ok, lv, html} = live(conn, ~p"/teams/#{team}/activities")

      assert html =~ "Swiftwater course"
      assert html =~ "Last week course"
      assert html =~ "Missing hiker"
      assert has_element?(lv, "#activity_collection .badge", "Rope")
      assert has_element?(lv, "select[name='form[status]']")
      assert has_element?(lv, "select[name='form[hours]']")
      refute has_element?(lv, ".tabs")
      refute has_element?(lv, "#activity-add")
      assert has_element?(lv, "#side-nav-activities[aria-current=page]")
    end
  end
end
