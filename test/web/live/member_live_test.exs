defmodule Web.MemberLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

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

  test "shows a team admin the emergency contacts, with Call and Text", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    member =
      member_fixture(team, %{
        primary_emergency_contact: %{
          "name" => "Sam Rivera",
          "relation" => "Partner",
          "primary_phone" => "6045550100",
          "secondary_phone" => "604-555-0101"
        },
        secondary_emergency_contact: %{"name" => nil, "primary_phone" => nil}
      })

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    assert has_element?(lv, "#member-emergency", "Sam Rivera (Partner)")
    assert has_element?(lv, "#member-emergency", "604-555-0101")
    assert has_element?(lv, ~s|#member-emergency-copy-0[value="604-555-0100"]|)
    assert has_element?(lv, ~s|#member-emergency-call[href="tel:+16045550100"]|)
    refute has_element?(lv, "#member-emergency-2")
  end

  test "shows a team admin the second emergency contact when it has a name or a phone",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    member =
      member_fixture(team, %{
        primary_emergency_contact: %{"name" => "Sam Rivera"},
        secondary_emergency_contact: %{"name" => "Lee Chan", "primary_phone" => "6045550102"}
      })

    phone_only =
      member_fixture(team, %{secondary_emergency_contact: %{"primary_phone" => "6045550103"}})

    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}")
    assert has_element?(lv, "#member-emergency", "Sam Rivera")
    assert has_element?(lv, "#member-emergency-2", "Lee Chan")
    assert has_element?(lv, ~s|#member-emergency-2-call[href="tel:+16045550102"]|)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{phone_only.id}")
    assert has_element?(lv, "#member-emergency", "None")
    assert has_element?(lv, "#member-emergency-2", "604-555-0103")
  end

  test "a member with no emergency contact shows None", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    assert has_element?(lv, "#member-emergency", "None")
  end

  test "a member can't open another member's page, so never sees their contacts", %{conn: conn} do
    %{team: team, user: user} = member_with_login_fixture()
    other = member_fixture(team, %{primary_emergency_contact: %{"name" => "Sam Rivera"}})

    assert_raise Web.Status.NotFound, fn ->
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{other.id}")
    end
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

  test "the Tag filter keeps the activities with the tag", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    tag_fixture(team, "Swiftwater")
    member = member_fixture(team)
    recent = DateTime.add(DateTime.utc_now(), -10, :day)

    swift =
      activity_fixture(team, %{
        title: "River day",
        tags: ["Swiftwater", "Primary Hours"],
        started_at: recent
      })

    attendance_fixture(swift, member, %{duration_in_minutes: 300, started_at: recent})
    attendance_fixture(activity_fixture(team, %{title: "Board meeting"}), member)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members/#{member.id}?when=all&activity_tag=Swiftwater")

    assert has_element?(lv, "#attendance_collection", "River day")
    refute has_element?(lv, "#attendance_collection", "Board meeting")
    assert has_element?(lv, "#attendance_filter_form-summary", "1 activity")
    assert has_element?(lv, "#attendance_filter_form-summary", "5 hours total")

    # The members list's rolling periods open here too.
    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members/#{member.id}?when=365d&activity_tag=Swiftwater")

    assert has_element?(lv, "#attendance_collection", "River day")
  end
end
