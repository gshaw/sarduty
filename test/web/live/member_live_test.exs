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

  test "the header says the role, when they joined, and when they last attended (#367)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    member =
      member_fixture(team, %{position: "Ground searcher", joined_at: ~U[2016-10-03 16:00:00Z]})

    never = member_fixture(team)
    activity = activity_fixture(team, %{started_at: ~U[2026-01-10 18:00:00Z]})
    attendance_fixture(activity, member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    assert has_element?(
             lv,
             "#member-head-facts",
             "Ground searcher · Joined October 2016 · Last attended Jan 10, 2026"
           )

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{never.id}")
    assert has_element?(lv, "#member-head-facts", "Not attended yet")
  end

  test "every tab opens with the same header and View as member", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    conn = log_in_user(conn, user)

    for tab <- ["", "/qualifications", "/groups", "/standing", "/card", "/history"] do
      {:ok, lv, _html} = live(conn, "/teams/#{team.subdomain}/members/#{member.id}#{tab}")

      assert has_element?(lv, "#member-head h1", member.name)
      assert has_element?(lv, "#view-as", "View as member")
    end
  end

  test "the sidebar lists 5 items the member holds by title, then all of them (#490)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    items =
      for n <- 1..6,
          do:
            equipment_item_fixture(team, %{
              title: "Radio #{n}",
              member_id: member.id,
              barcode: "R-#{n}"
            })

    old =
      equipment_item_fixture(team, %{title: "Radio 0", member_id: member.id, status: "retired"})

    other = member_fixture(team)
    equipment_item_fixture(team, %{title: "Their radio", member_id: other.id})
    # An id from another team never reaches this team's member.
    equipment_item_fixture(team_fixture(), %{title: "Stray radio", member_id: member.id})
    conn = log_in_user(conn, user)

    for tab <- ["", "/history"] do
      {:ok, lv, _html} = live(conn, "/teams/#{team.subdomain}/members/#{member.id}#{tab}")

      [first | _rest] = items
      sixth = List.last(items)
      assert has_element?(lv, "#member-equipment-#{first.id} a", "Radio 1")
      assert has_element?(lv, "#member-equipment-#{first.id} .hint", "Radio · R-1")
      refute has_element?(lv, "#member-equipment-#{sixth.id}")
      # D4H still has a retired item with the member, so the team may want it back.
      assert has_element?(lv, "#member-equipment-#{old.id} .badge", "Retired")
      refute has_element?(lv, "#member-equipment", "Their radio")
      refute has_element?(lv, "#member-equipment", "Stray radio")

      assert has_element?(
               lv,
               ~s{#member-equipment-all[href="/teams/#{team.subdomain}/equipment?place=member-#{member.id}&show=all"]},
               "All 7 items"
             )
    end

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{other.id}")
    assert has_element?(lv, "#member-equipment", "Their radio")
    refute has_element?(lv, "#member-equipment-all")
  end

  test "a retired member who holds items: the badge counts them on every tab (#490)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{left_at: ~U[2026-09-30 19:00:00Z], d4h_status: "RETIRED"})
    # A pack with a radio in it counts both, and a retired item counts, as the sidebar
    # lists them.
    pack = equipment_item_fixture(team, %{title: "Pack 3", member_id: member.id})
    equipment_item_fixture(team, %{title: "Radio 9", d4h_container_id: pack.d4h_equipment_id})
    equipment_item_fixture(team, %{title: "Helmet 9", member_id: member.id})
    equipment_item_fixture(team, %{title: "Old radio", member_id: member.id, status: "retired"})
    equipment_item_fixture(team_fixture(), %{title: "Stray radio", member_id: member.id})
    conn = log_in_user(conn, user)

    for tab <- ["", "/history", "/standing", "/qualifications", "/groups"] do
      {:ok, lv, _html} = live(conn, "/teams/#{team.subdomain}/members/#{member.id}#{tab}")

      assert has_element?(lv, "#member-head-standing.badge-warning", "Retired with 4 items")
    end
  end

  test "a retired member whose only item is retired: D4H still has it with them",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{left_at: ~U[2026-01-01 08:00:00Z]})
    equipment_item_fixture(team, %{title: "Old radio", member_id: member.id, status: "retired"})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    assert has_element?(lv, "#member-head-standing.badge-warning", "Retired with 1 item")
  end

  test "a retired member who holds nothing keeps the grey Retired badge", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{left_at: ~U[2026-01-01 08:00:00Z]})
    equipment_item_fixture(team_fixture(), %{title: "Stray radio", member_id: member.id})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    assert has_element?(lv, "#member-head-standing", "Retired")
    refute has_element?(lv, "#member-head-standing.badge-warning")
  end

  test "a current member who holds items has no badge", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    equipment_item_fixture(team, %{member_id: member.id})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    refute has_element?(lv, "#member-head-standing")
  end

  test "a member who holds nothing has no Equipment in the sidebar", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    refute has_element?(lv, "#member-equipment")
    refute has_element?(lv, "dt", "Equipment")
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
