defmodule Web.TakeAttendanceLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), team: team}
  end

  defp hours_from_now(hours),
    do: DateTime.utc_now() |> DateTime.add(hours, :hour) |> DateTime.truncate(:second)

  defp at(team, starts_in_hours, attrs \\ %{}) do
    started_at = hours_from_now(starts_in_hours)

    activity_fixture(
      team,
      Map.merge(%{started_at: started_at, finished_at: DateTime.add(started_at, 2, :hour)}, attrs)
    )
  end

  test "with one activity now, opens its scanner", %{conn: conn, team: team} do
    activity = at(team, 1)
    at(team, 30)
    at(team_fixture(), 0)

    scanner = ~p"/teams/#{team}/activities/#{activity.id}/take-attendance"

    assert {:error, {:live_redirect, %{to: ^scanner}}} =
             live(conn, ~p"/teams/#{team}/take-attendance")
  end

  test "with several, lists each, oldest start first", %{conn: conn, team: team} do
    rope = at(team, -1, %{title: "Rope practice", address: "Murrin Park"})
    first_aid = at(team, 1, %{title: "First aid"})
    deleted = at(team, 0, %{deleted_at: ~U[2026-10-05 06:00:00Z]})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/take-attendance")

    assert has_element?(lv, "#activity-#{rope.id}", "Rope practice")
    assert has_element?(lv, "#activity-#{rope.id}", "Murrin Park")

    assert has_element?(
             lv,
             ~s{#activity-#{first_aid.id}[href="/teams/#{team.subdomain}/activities/#{first_aid.id}/take-attendance"]}
           )

    refute has_element?(lv, "#activity-#{deleted.id}")
    assert render(lv) =~ ~r/Rope practice.*First aid/s
  end

  test "with none, says when the next one opens", %{conn: conn, team: team} do
    next = at(team, 48, %{title: "Swiftwater"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/take-attendance")
    assert has_element?(lv, "#no-activity", "No activity now.")
    assert has_element?(lv, "#next-#{next.id}", "Swiftwater")
    assert has_element?(lv, "#opens-at", "Taking attendance opens at")
    assert has_element?(lv, "#opens-at", "2 hours before it starts.")

    assert has_element?(
             lv,
             ~s{#next-activity a[href="/teams/#{team.subdomain}/activities/#{next.id}"]}
           )
  end

  # The tick stands in for the clock: moving the activity moves its window over now.
  test "left open, it opens the scanner when an activity's window opens", %{
    conn: conn,
    team: team
  } do
    later = at(team, 3)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/take-attendance")
    assert has_element?(lv, "#next-#{later.id}")

    later
    |> Ecto.Changeset.change(started_at: hours_from_now(1), finished_at: hours_from_now(3))
    |> Repo.update!()

    send(lv.pid, :tick)
    assert_redirect(lv, ~p"/teams/#{team}/activities/#{later.id}/take-attendance")
  end

  test "with nothing coming up, says so", %{conn: conn, team: team} do
    at(team, -48)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/take-attendance")
    assert has_element?(lv, "#nothing-coming", "Nothing coming up.")
  end

  test "shows its own address to copy", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/take-attendance")

    assert has_element?(lv, ~s{#page-url[href$="/teams/#{team.subdomain}/take-attendance"]})
    assert has_element?(lv, "#copy-page-url", "Copy link")
    assert has_element?(lv, "#page-address", "print a QR code")
  end

  test "the scanner links back here while another activity is on", %{conn: conn, team: team} do
    rope = at(team, -1)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{rope.id}/take-attendance")
    refute has_element?(lv, "#other-activities")

    at(team, 1)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{rope.id}/take-attendance")

    assert has_element?(
             lv,
             ~s{#other-activities[href="/teams/#{team.subdomain}/take-attendance"]}
           )
  end

  test "a scanner left on last week's activity links to the one on now", %{
    conn: conn,
    team: team
  } do
    last_week = at(team, -170)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{last_week.id}/take-attendance")
    refute has_element?(lv, "#other-activities")

    at(team, 1)
    send(lv.pid, :tick)

    assert has_element?(
             lv,
             ~s{#other-activities[href="/teams/#{team.subdomain}/take-attendance"]}
           )
  end

  test "the side navigation links here", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities")

    assert has_element?(
             lv,
             ~s{a[href="/teams/#{team.subdomain}/take-attendance"]},
             "Take attendance"
           )
  end

  describe "for a member" do
    test "opens it on a team with member logins" do
      %{team: team, user: user} = member_with_login_fixture()
      at(team, 48)

      {:ok, lv, _html} = live(log_in_user(build_conn(), user), ~p"/teams/#{team}/take-attendance")
      assert has_element?(lv, "#no-activity")
    end

    test "gets a 404 on a team with member logins off" do
      team = team_fixture()
      member = member_fixture(team, %{d4h_permission: 2})
      conn = log_in_user(build_conn(), user_fixture(%{email: member.email}))

      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/take-attendance") end
    end
  end

  describe "logged out" do
    test "goes to the login page, which says what it's for, and comes back after", %{
      team: team
    } do
      conn = get(build_conn(), ~p"/teams/#{team}/take-attendance")
      assert redirected_to(conn) == ~p"/login"
      assert get_session(conn, :user_return_to) == "/teams/#{team.subdomain}/take-attendance"
      # No toast to cover the line on the login page.
      refute Phoenix.Flash.get(conn.assigns.flash, :error)

      {:ok, lv, _html} = conn |> recycle() |> live(~p"/login")
      assert has_element?(lv, "#login-take-attendance", "Log in to take attendance.")

      conn =
        Phoenix.ConnTest.init_test_session(build_conn(), %{
          user_return_to: "/teams/#{team.subdomain}/take-attendance",
          login_email: "pat@example.com"
        })

      {:ok, lv, _html} = live(conn, ~p"/login/code")
      assert has_element?(lv, "#login-take-attendance")
      assert has_element?(lv, "#remember-shared-device", "leave this unticked")
    end

    test "another team page keeps the toast", %{team: team} do
      conn = get(build_conn(), ~p"/teams/#{team}")
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Log in to see this page."
    end

    test "other pages don't add the lines" do
      {:ok, lv, _html} = live(build_conn(), ~p"/login")
      refute has_element?(lv, "#login-take-attendance")

      conn = Phoenix.ConnTest.init_test_session(build_conn(), %{login_email: "pat@example.com"})
      {:ok, lv, _html} = live(conn, ~p"/login/code")
      refute has_element?(lv, "#login-take-attendance")
      refute has_element?(lv, "#remember-shared-device")
    end
  end

  test "path? knows both Take attendance pages" do
    assert Web.TakeAttendanceLive.path?("/teams/squamish/take-attendance")
    assert Web.TakeAttendanceLive.path?("/teams/squamish/activities/12/take-attendance")
    refute Web.TakeAttendanceLive.path?("/teams/squamish/activities/12/attendance")
    refute Web.TakeAttendanceLive.path?("/teams/squamish")
    refute Web.TakeAttendanceLive.path?(nil)
  end
end
