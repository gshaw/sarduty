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

  describe "for a member (#440)" do
    setup %{conn: conn} do
      %{team: team, user: user, member: member} = member_with_login_fixture()
      %{conn: log_in_user(conn, user), team: team, member: member}
    end

    test "the team admin's page without contact details, Actions, or View as member",
         %{conn: conn, team: team} do
      other =
        member_fixture(team, %{
          ref_id: "M-42",
          phone: "6045551234",
          address: "12 Elm St",
          primary_emergency_contact: %{"name" => "Sam Rivera"}
        })

      {:ok, lv, html} = live(conn, ~p"/teams/#{team}/members/#{other.id}")

      assert has_element?(lv, "#member-head", other.name)
      assert has_element?(lv, "dd", "M-42")
      assert has_element?(lv, "#member-milestones")
      refute has_element?(lv, "#member-phone")
      refute has_element?(lv, "#member-emergency")
      refute has_element?(lv, "#member-copy-email")
      refute has_element?(lv, "#member-actions")
      refute has_element?(lv, "#view-as")
      refute html =~ other.email
      refute html =~ "Sam Rivera"
    end

    test "Attendance, Qualifications, and Groups tabs only", %{conn: conn, team: team} do
      other = member_fixture(team)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{other.id}")

      for tab <- ["qualifications", "groups"] do
        assert has_element?(lv, ~s{a[href="/teams/#{team.subdomain}/members/#{other.id}/#{tab}"]})
      end

      for tab <- ["standing", "card", "history"] do
        refute has_element?(lv, ~s{a[href="/teams/#{team.subdomain}/members/#{other.id}/#{tab}"]})

        assert_raise Web.Status.NotFound, fn ->
          live(conn, ~p"/teams/#{team}/members/#{other.id}/#{tab}")
        end
      end
    end

    test "the header badges Retired, never Away or Not a person", %{conn: conn, team: team} do
      away = member_fixture(team)
      away_period_fixture(away, Date.add(Date.utc_today(), -5), Date.add(Date.utc_today(), 30))
      bot = member_fixture(team, %{not_a_person: true})
      retired = member_fixture(team, %{d4h_status: "RETIRED"})

      for other <- [away, bot] do
        {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{other.id}")
        refute has_element?(lv, "#member-head-standing")
      end

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{retired.id}")
      assert has_element?(lv, "#member-head-standing", "Retired")
    end

    test "their own member page opens Your membership", %{conn: conn, team: team, member: member} do
      for path <- ["", "/qualifications", "/groups"] do
        assert {:error, {:live_redirect, %{to: to}}} =
                 live(conn, "/teams/#{team.subdomain}/members/#{member.id}#{path}")

        assert to == ~p"/teams/#{team}/me"
      end
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

  test "a member who holds something gets the Equipment tab, not a sidebar line (#490)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    equipment_item_fixture(team, %{title: "Radio 1", member_id: member.id})
    conn = log_in_user(conn, user)
    tab = "/teams/#{team.subdomain}/members/#{member.id}/equipment"

    for path <- ["", "/history"] do
      {:ok, lv, _html} = live(conn, "/teams/#{team.subdomain}/members/#{member.id}#{path}")

      assert has_element?(lv, ~s{nav.tabs a[href="#{tab}"]}, "Equipment")
      refute has_element?(lv, "dt", "Equipment")
    end
  end

  test "a member who holds nothing has no Equipment in the sidebar or the tabs",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    refute has_element?(lv, "dt", "Equipment")
    refute has_element?(lv, "nav.tabs a", "Equipment")
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
