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

  test "the link closes a day after the activity ends", %{conn: conn, team: team} do
    ended = DateTime.utc_now() |> DateTime.add(-25, :hour) |> DateTime.truncate(:second)

    activity =
      activity_fixture(team, %{started_at: DateTime.add(ended, -1, :hour), finished_at: ended})

    link = CreateAttendanceLink.call(team, activity, user_fixture(), DateTime.utc_now())
    {:ok, lv, _html} = live(conn, ~p"/attendance/#{link.token}")
    assert has_element?(lv, "#link-closed")
  end
end
