defmodule Web.MemberLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  test "renders member page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members/#{member.id}")

    assert html =~ member.name
  end

  test "shows the phone number to read, and Call and Text for touch screens", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{phone: "6045551234"})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    assert has_element?(lv, "#member-phone", "604-555-1234")
    assert has_element?(lv, ~s|#member-copy-phone[value="604-555-1234"]|)
    assert has_element?(lv, ~s|#member-copy-email[value="#{member.email}"]|)
    assert has_element?(lv, ~s|#member-phone-call[href="tel:+16045551234"]|)
    assert has_element?(lv, ~s|#member-phone-text[href="sms:+16045551234"]|)
  end

  test "opens the member's address in maps without their name", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{name: "Kim Ng", address: "12 Elm St\nSurrey BC"})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    assert has_element?(lv, ~s|#member-maps[href$="query=12+Elm+St%2C+Surrey+BC"]|)
    assert has_element?(lv, ~s|#member-copy-address[value="12 Elm St, Surrey BC"]|)
    refute render(lv) =~ "query=Kim"
  end

  test "search finds the member's activities by title (#350)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    attendance_fixture(activity_fixture(team, %{title: "Rope rescue night"}), member)
    attendance_fixture(activity_fixture(team, %{title: "Board meeting"}), member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}?when=all")

    lv |> form("#attendance_filter_form", filter: %{q: "rope"}) |> render_change()

    assert has_element?(lv, "#attendance_collection", "Rope rescue night")
    refute has_element?(lv, "#attendance_collection", "Board meeting")
    assert has_element?(lv, "#attendance_filter_form-summary", "1 activity")
  end

  test "the summary says when the member last attended (#367)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    never = member_fixture(team)
    activity = activity_fixture(team, %{started_at: ~U[2026-01-10 18:00:00Z]})
    attendance_fixture(activity, member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    assert has_element?(lv, "#member-last-attended", "Jan 10, 2026")

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{never.id}")
    assert has_element?(lv, "#member-last-attended", "Never")
  end
end
