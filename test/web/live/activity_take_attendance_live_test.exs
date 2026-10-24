defmodule Web.ActivityTakeAttendanceLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.AttendanceScan
  alias App.Model.MemberCard
  alias App.Repo

  # A team admin, and an activity running now.
  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity = team |> activity_fixture() |> Repo.preload(:team)

    %{
      conn: log_in_user(conn, user),
      user: user,
      team: team,
      activity: activity,
      path: ~p"/teams/#{team}/activities/#{activity.id}/take-attendance",
      member: member_fixture(team, %{name: "Mei Chen"})
    }
  end

  defp scans(activity), do: AttendanceScan.get_all(activity)

  defp hours_from_now(hours),
    do: DateTime.utc_now() |> DateTime.add(hours, :hour) |> DateTime.truncate(:second)

  defp pick(lv, member) do
    lv
    |> form("#door-form")
    |> put_submitter("#pick-#{member.id}")
    |> render_submit()
  end

  test "a team admin opens it from the activity", %{conn: conn, path: path, activity: activity} do
    {:ok, lv, _html} = live(conn, path)
    assert has_element?(lv, "h1", activity.title)
    assert has_element?(lv, "#activity-summary", "Today")
    assert has_element?(lv, "#scanner[data-continuous]")
    assert has_element?(lv, ~s(#sound-switch[role="switch"]))
    assert has_element?(lv, "#no-scans")

    assert has_element?(
             lv,
             ~s{#send-attendance[href="/teams/#{activity.team.subdomain}/activities/#{activity.id}/attendance"]}
           )
  end

  test "a team admin takes attendance long after the activity", %{conn: conn, team: team} do
    activity =
      activity_fixture(team, %{started_at: hours_from_now(-72), finished_at: hours_from_now(-70)})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/take-attendance")
    assert has_element?(lv, "#controls")
    refute has_element?(lv, "#closed")
  end

  test "an activity deleted in D4H goes back to its page", %{conn: conn, team: team} do
    activity = activity_fixture(team, %{deleted_at: ~U[2026-10-05 06:00:00Z]})
    activity_path = ~p"/teams/#{team}/activities/#{activity.id}"

    assert {:error, {:live_redirect, %{to: ^activity_path}}} =
             live(conn, "#{activity_path}/take-attendance")
  end

  test "an activity deleted while the page is open takes no scans", %{
    conn: conn,
    path: path,
    activity: activity,
    member: member
  } do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, path)

    activity |> Ecto.Changeset.change(deleted_at: ~U[2026-10-05 06:00:00Z]) |> Repo.update!()
    render_hook(lv, "scanned", %{code: card.code})

    assert_redirect(lv, ~p"/teams/#{activity.team}/activities/#{activity.id}")
    assert scans(activity) == []
  end

  test "another team's activity is not found", %{conn: conn, team: team} do
    other = team_fixture() |> activity_fixture()

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/teams/#{team}/activities/#{other.id}/take-attendance")
    end
  end

  test "a scan records who took it", %{
    conn: conn,
    path: path,
    user: user,
    team: team,
    activity: activity,
    member: member
  } do
    {:ok, lv, _html} = live(conn, path)
    lv |> form("#door-form", search: "mei") |> render_change()
    pick(lv, member)

    recorder = Repo.get_by!(App.Model.Member, team_id: team.id, email: user.email)
    user_id = user.id
    recorder_id = recorder.id

    assert [%{recorded_by_user_id: ^user_id, recorded_by_member_id: ^recorder_id}] =
             scans(activity)
  end

  test "an ID card scan records the member arriving", %{
    conn: conn,
    path: path,
    activity: activity,
    member: member
  } do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, path)

    url = MemberCard.qr_url(card.code, Web.VerifyHost.url())
    render_hook(lv, "scanned", %{code: url})

    assert has_element?(lv, "#message", "Mei Chen arrived at")
    assert [%{kind: "arrived", method: "card"}] = scans(activity)
    assert has_element?(lv, "#scans", "Mei Chen")
    assert has_element?(lv, "#scans", "Arrived")
  end

  test "leaving is recorded when Leaving is selected", %{
    conn: conn,
    path: path,
    activity: activity,
    member: member
  } do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, path)

    lv |> element("#kind-left") |> render_click()
    render_hook(lv, "scanned", %{code: card.code})

    assert has_element?(lv, "#message", "Mei Chen left at")
    assert [%{kind: "left"}] = scans(activity)
  end

  test "a card from another team, or a cancelled one, records nothing", %{
    conn: conn,
    path: path,
    activity: activity,
    member: member
  } do
    other = team_fixture() |> member_fixture() |> member_card_fixture()
    cancelled = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})
    {:ok, lv, _html} = live(conn, path)

    render_hook(lv, "scanned", %{code: other.code})
    assert has_element?(lv, "#message", "another team")

    render_hook(lv, "scanned", %{code: cancelled.code})
    assert has_element?(lv, "#message", "cancelled")

    render_hook(lv, "scanned", %{code: "https://example.com/K7Q4-M2XA"})
    assert has_element?(lv, "#message", "not a SAR Duty ID card")

    assert scans(activity) == []
  end

  test "a member without a card is found by name", %{
    conn: conn,
    path: path,
    activity: activity,
    member: member
  } do
    {:ok, lv, _html} = live(conn, path)

    lv |> form("#door-form", search: "mei") |> render_change()
    pick(lv, member)

    assert has_element?(lv, "#message", "Mei Chen arrived at")
    assert [%{method: "name"}] = scans(activity)
  end

  test "picking a member from another team records nothing", %{
    conn: conn,
    path: path,
    activity: activity
  } do
    other = team_fixture() |> member_fixture()
    {:ok, lv, _html} = live(conn, path)

    render_submit(lv, "pick", %{"pick" => other.id})
    assert scans(activity) == []
  end

  test "a typed time is recorded with the scan", %{
    conn: conn,
    path: path,
    activity: activity,
    member: member
  } do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, path)

    lv |> form("#door-form", override: "09:15") |> render_change()
    render_hook(lv, "scanned", %{code: card.code})

    assert has_element?(lv, "#message", "arrived at 09:15")
    assert [%{override_at: %DateTime{}}] = scans(activity)
  end

  test "undo removes a scan", %{conn: conn, path: path, activity: activity, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, path)
    render_hook(lv, "scanned", %{code: card.code})
    [scan] = scans(activity)

    lv |> element("#undo-#{scan.id}") |> render_click()
    assert scans(activity) == []
    assert has_element?(lv, "#no-scans")
  end

  test "a typed time shows until it's cleared", %{conn: conn, path: path} do
    {:ok, lv, _html} = live(conn, path)
    refute has_element?(lv, "#override-note")

    lv |> form("#door-form", override: "14:30") |> render_change()
    assert has_element?(lv, "#override-note", "Recording as 14:30")

    lv |> element("#clear-override") |> render_click()
    refute has_element?(lv, "#override-note")
  end

  test "a good scan's confirmation clears for the next one", %{
    conn: conn,
    path: path,
    team: team,
    activity: activity,
    member: member
  } do
    {:ok, lv, _html} = live(conn, path)
    lv |> form("#door-form", search: "mei") |> render_change()
    pick(lv, member)
    assert has_element?(lv, "#message", "Mei Chen arrived at")

    # A timer from an older scan leaves the newer confirmation alone.
    send(lv.pid, {:clear_message, {:arrived, "Sam Ortiz arrived at 09:00."}})
    assert has_element?(lv, "#message")

    [scan] = scans(activity)
    time = scan |> AttendanceScan.time() |> Service.Format.time_short(team.timezone)
    send(lv.pid, {:clear_message, {:arrived, "Mei Chen arrived at #{time}."}})
    refute has_element?(lv, "#message")
  end

  # The phone may never send a change for the time box, so a pick reads it from the form.
  test "a typed time is recorded with a member picked by name", %{
    conn: conn,
    path: path,
    activity: activity,
    member: member
  } do
    {:ok, lv, _html} = live(conn, path)
    lv |> form("#door-form", search: "mei") |> render_change()

    lv
    |> form("#door-form", override: "09:15", search: "mei")
    |> put_submitter("#pick-#{member.id}")
    |> render_submit()

    assert has_element?(lv, "#message", "Mei Chen arrived at 09:15")
    assert [%{method: "name", override_at: %DateTime{}}] = scans(activity)
  end

  test "a scan uses the time the scanner sends with it", %{
    conn: conn,
    path: path,
    activity: activity,
    member: member
  } do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, path)

    render_hook(lv, "scanned", %{code: card.code, override: "09:15"})

    assert has_element?(lv, "#message", "arrived at 09:15")
    assert [%{override_at: %DateTime{}}] = scans(activity)
  end

  test "enter in the search box records nothing", %{conn: conn, path: path, activity: activity} do
    {:ok, lv, _html} = live(conn, path)
    lv |> form("#door-form", search: "mei") |> render_submit()

    assert has_element?(lv, "#matches")
    assert scans(activity) == []
  end

  describe "a plug-in barcode scanner in the name box" do
    test "enter with a card's link records the card and empties the box", %{
      conn: conn,
      path: path,
      activity: activity,
      member: member
    } do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, path)

      url = MemberCard.qr_url(card.code, Web.VerifyHost.url())
      lv |> form("#door-form", search: url) |> render_submit()

      assert has_element?(lv, "#message", "Mei Chen arrived at")
      assert [%{kind: "arrived", method: "card"}] = scans(activity)
      assert_push_event(lv, "clear-search", %{})
      assert_push_event(lv, "scan-sound", %{sound: :arrived})
    end

    test "enter with a printed code records the card, with the typed time", %{
      conn: conn,
      path: path,
      activity: activity,
      member: member
    } do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, path)

      code = MemberCard.format_code(card.code)
      lv |> form("#door-form", search: code, override: "09:15") |> render_submit()

      assert has_element?(lv, "#message", "arrived at 09:15")
      assert [%{method: "card", override_at: %DateTime{}}] = scans(activity)
    end

    test "a cancelled card's code records nothing", %{
      conn: conn,
      path: path,
      activity: activity,
      member: member
    } do
      card = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})
      {:ok, lv, _html} = live(conn, path)

      lv |> form("#door-form", search: MemberCard.format_code(card.code)) |> render_submit()

      assert has_element?(lv, "#message", "cancelled")
      assert scans(activity) == []
    end

    test "a link being typed shows no \"no member\" line", %{conn: conn, path: path} do
      {:ok, lv, _html} = live(conn, path)

      lv |> form("#door-form", search: "HTTPS://VERIF") |> render_change()
      refute has_element?(lv, "#no-matches")

      lv |> form("#door-form", search: "zz") |> render_change()
      assert has_element?(lv, "#no-matches")
    end

    test "the box carries the scanner hook", %{conn: conn, path: path} do
      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, ~s(#search[phx-hook="ScannerInput"]))
      assert has_element?(lv, "#kind-left[data-return-focus]")
    end
  end

  test "card_entry? tells a card from a name" do
    assert Web.ActivityTakeAttendanceLive.card_entry?("HTTPS://VERIFY.SARDUTY.COM/K7Q4-M2XA")
    assert Web.ActivityTakeAttendanceLive.card_entry?("K7Q4-M2XA")
    assert Web.ActivityTakeAttendanceLive.card_entry?("k7q4m2xa")
    refute Web.ActivityTakeAttendanceLive.card_entry?("Matthews")
    refute Web.ActivityTakeAttendanceLive.card_entry?("mei")
  end

  test "each scan plays a sound for its result", %{conn: conn, path: path, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, path)

    render_hook(lv, "scanned", %{code: card.code})
    assert_push_event(lv, "scan-sound", %{sound: :arrived})

    lv |> element("#kind-left") |> render_click()
    render_hook(lv, "scanned", %{code: card.code})
    assert_push_event(lv, "scan-sound", %{sound: :left})

    render_hook(lv, "scanned", %{code: "ZZZZ-ZZZZ"})
    assert_push_event(lv, "scan-sound", %{sound: :error})
  end

  describe "yet to arrive" do
    test "lists who signed up and has not arrived, and drops a member once scanned", %{
      conn: conn,
      team: team,
      path: path,
      activity: activity,
      member: member
    } do
      raj = member_fixture(team, %{name: "Raj Patel", phone: "604 555 1234"})
      attendance_fixture(activity, member, %{status: "attending"})
      attendance_fixture(activity, raj, %{status: "attending"})
      attendance_fixture(activity, member_fixture(team), %{status: "absent"})
      # An invite nobody replied to is not a sign-up.
      attendance_fixture(activity, member_fixture(team), %{status: "requested"})

      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "#toggle-yet-to-arrive", "2 of 2 signed up")
      refute has_element?(lv, "#yet-to-arrive")

      lv |> element("#toggle-yet-to-arrive") |> render_click()
      assert has_element?(lv, "#yet-to-arrive-member-#{raj.id}", "604-555-1234")
      assert has_element?(lv, ~s|#yet-to-arrive-#{raj.id}-call[href="tel:+16045551234"]|)
      assert has_element?(lv, ~s|#yet-to-arrive-#{raj.id}-text[href="sms:+16045551234"]|)

      lv |> form("#door-form", %{search: "Raj"}) |> render_change()
      pick(lv, raj)
      refute has_element?(lv, "#yet-to-arrive-member-#{raj.id}")
      assert has_element?(lv, "#yet-to-arrive-member-#{member.id}")
      assert has_element?(lv, "#toggle-yet-to-arrive", "1 of 2 signed up")
      assert has_element?(lv, "#yet-to-arrive-count", "1 member arrived.")
    end

    test "shows no button when nobody signed up", %{conn: conn, path: path} do
      {:ok, lv, _html} = live(conn, path)
      refute has_element?(lv, "#toggle-yet-to-arrive")
    end
  end

  describe "for a member" do
    setup do
      %{team: team, user: user} = member_with_login_fixture()
      %{conn: log_in_user(build_conn(), user), team: team}
    end

    defp open_member(conn, team, activity),
      do: live(conn, ~p"/teams/#{team}/activities/#{activity.id}/take-attendance")

    test "takes attendance during the activity, and sees names only in yet to arrive", %{
      conn: conn,
      team: team
    } do
      activity = activity_fixture(team)
      raj = member_fixture(team, %{name: "Raj Patel", phone: "604 555 1234"})
      attendance_fixture(activity, raj, %{status: "attending"})

      {:ok, lv, _html} = open_member(conn, team, activity)
      assert has_element?(lv, "#controls")
      refute has_element?(lv, "#send-attendance")

      lv |> element("#toggle-yet-to-arrive") |> render_click()
      assert has_element?(lv, "#yet-to-arrive-member-#{raj.id}", "Raj Patel")
      refute has_element?(lv, "#yet-to-arrive-member-#{raj.id}", "604-555-1234")
      refute has_element?(lv, "#yet-to-arrive-#{raj.id}-call")

      lv |> form("#door-form", search: "Raj") |> render_change()
      pick(lv, raj)
      assert [%{member_id: raj_id}] = scans(activity)
      assert raj_id == raj.id
    end

    test "before the window opens, says when it does", %{conn: conn, team: team} do
      activity =
        activity_fixture(team, %{started_at: hours_from_now(5), finished_at: hours_from_now(6)})

      {:ok, lv, _html} = open_member(conn, team, activity)
      assert has_element?(lv, "#closed", "You can take attendance from")
      assert has_element?(lv, "#closed", "2 hours before it starts.")
      refute has_element?(lv, "#controls")
    end

    test "after the window closes, says who adds anyone missing", %{conn: conn, team: team} do
      activity =
        activity_fixture(team, %{started_at: hours_from_now(-6), finished_at: hours_from_now(-3)})

      {:ok, lv, _html} = open_member(conn, team, activity)
      assert has_element?(lv, "#closed", "Taking attendance closed at")
      assert has_element?(lv, "#closed", "Ask a team admin to add anyone missing.")
      refute has_element?(lv, "#controls")
    end

    test "a page left open stops taking scans when the window closes", %{
      conn: conn,
      team: team
    } do
      activity = activity_fixture(team)
      raj = member_fixture(team, %{name: "Raj Patel"})
      {:ok, lv, _html} = open_member(conn, team, activity)

      activity
      |> Ecto.Changeset.change(started_at: hours_from_now(-6), finished_at: hours_from_now(-3))
      |> Repo.update!()

      render_submit(lv, "pick", %{"pick" => raj.id})
      assert has_element?(lv, "#closed", "Taking attendance closed at")
      assert scans(activity) == []
    end

    test "on a team with member logins off, gets a 404" do
      off = team_fixture()
      member = member_fixture(off, %{d4h_permission: 2})
      conn = log_in_user(build_conn(), user_fixture(%{email: member.email}))
      activity = activity_fixture(off)

      assert_raise Web.Status.NotFound, fn -> open_member(conn, off, activity) end
    end
  end

  test "a team admin viewing as a member saves nothing", %{team: team, user: user} do
    team = team |> Ecto.Changeset.change(member_logins: true) |> Repo.update!()
    raj = member_fixture(team, %{name: "Raj Patel", phone: "604 555 1234"})
    activity = activity_fixture(team)
    attendance_fixture(activity, raj, %{status: "attending"})

    conn = build_conn() |> log_in_user(user)
    conn = post(conn, ~p"/teams/#{team}/members/#{raj}/view-as")

    {:ok, lv, _html} =
      live(conn, ~p"/teams/#{team}/activities/#{activity.id}/take-attendance")

    refute has_element?(lv, "#send-attendance")
    lv |> element("#toggle-yet-to-arrive") |> render_click()
    refute has_element?(lv, "#yet-to-arrive-#{raj.id}-call")

    lv |> form("#door-form", search: "Raj") |> render_change()
    pick(lv, raj)

    assert has_element?(lv, "#message", "so nothing is saved")
    assert scans(activity) == []
  end
end
