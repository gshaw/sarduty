defmodule Web.AttendanceLinkLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.AttendanceScan
  alias App.Model.MemberCard
  alias App.Operation.CloseAttendanceLink
  alias App.Operation.CreateAttendanceLink
  alias App.Repo

  # The activity runs now, so the link is open.
  setup do
    team = team_fixture()
    activity = team |> activity_fixture() |> Repo.preload(:team)
    link = CreateAttendanceLink.call(team, activity, user_fixture(), DateTime.utc_now())

    %{
      team: team,
      activity: activity,
      link: link,
      member: member_fixture(team, %{name: "Mei Chen"})
    }
  end

  defp scans(activity), do: AttendanceScan.get_all(activity)

  test "anyone with the link can open it without logging in", %{
    conn: conn,
    link: link,
    activity: activity
  } do
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")
    assert has_element?(lv, "#activity-summary", activity.title)
    assert has_element?(lv, "#scanner[data-continuous]")
    assert has_element?(lv, "#no-scans")
  end

  test "an unknown token shows the link as closed", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/attendance/not-a-token")
    assert has_element?(lv, "#link-closed")
  end

  test "a link on an activity deleted in D4H takes no scans", %{
    conn: conn,
    link: link,
    activity: activity,
    member: member
  } do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")

    activity |> Ecto.Changeset.change(deleted_at: ~U[2026-10-05 06:00:00Z]) |> Repo.update!()
    render_hook(lv, "scanned", %{code: card.code})

    assert has_element?(lv, "#link-closed")
    assert scans(activity) == []
  end

  test "an ID card scan records the member arriving", %{
    conn: conn,
    link: link,
    activity: activity,
    member: member
  } do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")

    url = MemberCard.qr_url(card.code, Web.VerifyHost.url())
    render_hook(lv, "scanned", %{code: url})

    assert has_element?(lv, "#message", "Mei Chen arrived at")
    assert [%{kind: "arrived", method: "card"}] = scans(activity)
    assert has_element?(lv, "#scans", "Mei Chen")
    assert has_element?(lv, "#scans", "Arrived")
  end

  test "leaving is recorded when Leaving is selected", %{
    conn: conn,
    link: link,
    activity: activity,
    member: member
  } do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")

    lv |> element("#kind-left") |> render_click()
    render_hook(lv, "scanned", %{code: card.code})

    assert has_element?(lv, "#message", "Mei Chen left at")
    assert [%{kind: "left"}] = scans(activity)
  end

  test "a card from another team, or a cancelled one, records nothing", %{
    conn: conn,
    link: link,
    activity: activity,
    member: member
  } do
    other = team_fixture() |> member_fixture() |> member_card_fixture()
    cancelled = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")

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
    link: link,
    activity: activity,
    member: member
  } do
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")

    lv |> form("#search-form", search: "mei") |> render_change()
    lv |> element("#pick-#{member.id}") |> render_click()

    assert has_element?(lv, "#message", "Mei Chen arrived at")
    assert [%{method: "name"}] = scans(activity)
  end

  test "picking a member from another team records nothing", %{
    conn: conn,
    link: link,
    activity: activity
  } do
    other = team_fixture() |> member_fixture()
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")

    render_click(lv, "pick", %{id: other.id})
    assert scans(activity) == []
  end

  test "a typed time is recorded with the scan", %{
    conn: conn,
    link: link,
    activity: activity,
    member: member
  } do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")

    lv |> form("#override-form", override: "09:15") |> render_change()
    render_hook(lv, "scanned", %{code: card.code})

    assert has_element?(lv, "#message", "arrived at 09:15")
    assert [%{override_at: %DateTime{}}] = scans(activity)
  end

  test "undo removes a scan", %{conn: conn, link: link, activity: activity, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")
    render_hook(lv, "scanned", %{code: card.code})
    [scan] = scans(activity)

    lv |> element("#undo-#{scan.id}") |> render_click()
    assert scans(activity) == []
    assert has_element?(lv, "#no-scans")
  end

  test "closing the link stops the open page", %{
    conn: conn,
    link: link,
    team: team,
    activity: activity,
    member: member
  } do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")

    CloseAttendanceLink.call(team, activity, DateTime.utc_now())
    render_hook(lv, "scanned", %{code: card.code})

    assert has_element?(lv, "#link-closed")
    assert scans(activity) == []
  end

  test "undo does nothing once the link is closed", %{
    conn: conn,
    link: link,
    team: team,
    activity: activity,
    member: member
  } do
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")
    lv |> element("#search-form") |> render_change(%{search: "mei"})
    lv |> element("#pick-#{member.id}") |> render_click()
    [scan] = scans(activity)

    CloseAttendanceLink.call(team, activity, DateTime.utc_now())
    render_click(lv, "undo", %{"id" => scan.id})

    assert has_element?(lv, "#link-closed", "This attendance link is closed.")
    assert [_scan] = scans(activity)
  end

  test "a typed time shows until it's cleared", %{conn: conn, link: link} do
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")
    refute has_element?(lv, "#override-note")

    lv |> element("#override-form") |> render_change(%{override: "14:30"})
    assert has_element?(lv, "#override-note", "Recording as 14:30")

    lv |> element("#clear-override") |> render_click()
    refute has_element?(lv, "#override-note")
  end

  test "a good scan's confirmation clears for the next one", %{
    conn: conn,
    link: link,
    team: team,
    activity: activity,
    member: member
  } do
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")
    lv |> element("#search-form") |> render_change(%{search: "mei"})
    lv |> element("#pick-#{member.id}") |> render_click()
    assert has_element?(lv, "#message", "Mei Chen arrived at")

    # A timer from an older scan leaves the newer confirmation alone.
    send(lv.pid, {:clear_message, {:ok, "Sam Ortiz arrived at 09:00."}})
    assert has_element?(lv, "#message")

    [scan] = scans(activity)
    time = scan |> AttendanceScan.time() |> Service.Format.time_short(team.timezone)
    send(lv.pid, {:clear_message, {:ok, "Mei Chen arrived at #{time}."}})
    refute has_element?(lv, "#message")
  end

  test "a link made weeks after the activity ends still works", %{conn: conn, team: team} do
    ended = DateTime.utc_now() |> DateTime.add(-20, :day) |> DateTime.truncate(:second)

    activity =
      activity_fixture(team, %{started_at: DateTime.add(ended, -1, :hour), finished_at: ended})

    link = CreateAttendanceLink.call(team, activity, user_fixture(), DateTime.utc_now())
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")
    assert has_element?(lv, "#activity-summary")
  end

  test "the link stops working 30 days after it's made", %{
    conn: conn,
    team: team,
    activity: activity
  } do
    # To the second, as a caller may pass it.
    made =
      DateTime.utc_now()
      |> DateTime.add(-30, :day)
      |> DateTime.add(-1, :minute)
      |> DateTime.truncate(:second)

    link = CreateAttendanceLink.call(team, activity, user_fixture(), made)
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")
    assert has_element?(lv, "#link-closed")
  end
end
