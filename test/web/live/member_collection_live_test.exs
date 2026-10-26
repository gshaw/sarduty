defmodule Web.MemberCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders members collection", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members")

    assert html =~ "Members"
  end

  test "lists current members missing a mobile phone or an email, and what they lack",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    no_phone = member_fixture(team, %{phone: nil})
    no_email = member_fixture(team, %{email: ""})
    neither = member_fixture(team, %{phone: "", email: nil})
    complete = member_fixture(team)
    retired = member_fixture(team, %{phone: nil, left_at: ~U[2025-01-01 00:00:00Z]})
    other_team = member_fixture(team_fixture(), %{phone: nil})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members?details=missing")

    assert has_element?(lv, "#missing-#{no_phone.id}", "Mobile phone")
    assert has_element?(lv, "#missing-#{no_email.id}", "Email")
    assert has_element?(lv, "#missing-#{neither.id}", "Mobile phone, Email")
    refute has_element?(lv, "#missing-#{complete.id}")
    refute has_element?(lv, "#missing-#{retired.id}")
    refute has_element?(lv, "#missing-#{other_team.id}")
  end

  test "the Group filter lists the group's members only", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    rope = group_fixture(team, %{title: "Rope rescue"})
    in_rope = member_fixture(team, %{name: "Avery Rope"})
    member_fixture(team, %{name: "Blake Ground"})
    group_member_fixture(rope, in_rope)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members")

    lv |> form("#member_filter_form", form: %{group: rope.id}) |> render_change()

    assert has_element?(lv, "#member_collection", "Avery Rope")
    refute has_element?(lv, "#member_collection", "Blake Ground")
    assert has_element?(lv, ".filter-bar-chips a", "Rope rescue")

    # The combobox lists its empty option, All, so one pick clears the filter.
    assert has_element?(lv, "#form_group-combobox[data-clearable] option[value='']", "All")
    lv |> form("#member_filter_form", form: %{group: ""}) |> render_change()
    assert has_element?(lv, "#member_collection", "Blake Ground")
  end

  test "the Tag filter counts only the activities with the tag, and links to them",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    tag_fixture(team, "Rope Rescue")
    rope = activity_fixture(team, %{title: "Rope night", tags: ["Rope Rescue"]})
    other = activity_fixture(team, %{title: "Board meeting", tags: ["Primary Hours"]})
    avery = member_fixture(team, %{name: "Avery Rope"})
    blake = member_fixture(team, %{name: "Blake Ground"})
    attendance_fixture(rope, avery, %{duration_in_minutes: 180})
    attendance_fixture(other, avery, %{duration_in_minutes: 60})
    attendance_fixture(other, blake, %{duration_in_minutes: 60})

    # Another team's activity with the same tag counts for nothing here.
    other_team = team_fixture()

    attendance_fixture(
      activity_fixture(other_team, %{tags: ["Rope Rescue"]}),
      member_fixture(other_team)
    )

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members")

    lv
    |> form("#member_filter_form", form: %{when: "all", activity_tag: "Rope Rescue"})
    |> render_change()

    assert has_element?(lv, "#member_collection tr", "Avery Rope")
    assert has_element?(lv, "#member_collection tr", "3 hours")
    assert has_element?(lv, ".filter-bar-chips a", "Rope Rescue")

    assert has_element?(
             lv,
             ~s|a[href="/teams/#{team.subdomain}/members/#{avery.id}?when=all&activity_tag=Rope+Rescue"]|
           )

    blake_row = lv |> element("#member_collection tr", "Blake Ground") |> render()
    assert blake_row =~ ~r/>\s*0\s*</
  end

  test "another team's group finds no one", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    other_team = team_fixture()
    other_group = group_fixture(other_team)
    group_member_fixture(other_group, member_fixture(other_team, %{name: "Other Member"}))
    member_fixture(team, %{name: "Our Member"})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?group=#{other_group.id}")

    refute has_element?(lv, "#member_collection", "Our Member")
    refute has_element?(lv, "#member_collection", "Other Member")
  end

  test "lists members not at an activity in the team's time frame, with when they last were",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    joined = ~U[2025-01-01 00:00:00Z]
    old = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), -200, :day)})
    recent = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), -10, :day)})
    drifting = member_fixture(team, %{joined_at: joined})
    attendance_fixture(old, drifting)
    never = member_fixture(team, %{joined_at: joined})
    seen = member_fixture(team, %{joined_at: joined})
    attendance_fixture(recent, seen)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members?attended=90")

    assert has_element?(lv, "#member_filter_form select[name='form[attended]']")
    assert has_element?(lv, "#last-attended-#{drifting.id}")
    refute has_element?(lv, "#last-attended-#{drifting.id}", "Never")
    assert has_element?(lv, "#last-attended-#{never.id}", "Never")
    refute has_element?(lv, "#last-attended-#{seen.id}")
    # The clock's reason shows only when it isn't the last activity.
    refute has_element?(lv, "#clock-starts-#{drifting.id}")
    assert has_element?(lv, "#clock-starts-#{never.id}", "Joined")
  end

  test "the Attended filter offers every time frame, even with the setting off",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    team |> Ecto.Changeset.change(not_seen_days: nil) |> App.Repo.update!()
    joined = ~U[2025-01-01 00:00:00Z]
    old = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), -200, :day)})
    drifting = member_fixture(team, %{joined_at: joined})
    attendance_fixture(old, drifting)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members?attended=180")

    for days <- ~w(30 60 90 180 365),
        do: assert(has_element?(lv, "select[name='form[attended]'] option[value='#{days}']"))

    assert has_element?(lv, "#last-attended-#{drifting.id}")

    {:ok, lv, _html} = live(conn |> log_in_user(user), ~p"/teams/#{team}/members?attended=365")
    refute has_element?(lv, "#last-attended-#{drifting.id}")
  end

  test "an empty Attended filter shows no clock, the same as All", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} = live(conn |> log_in_user(user), ~p"/teams/#{team}/members?attended=")

    assert has_element?(lv, "#last-attended-#{member.id}")
    refute has_element?(lv, "#attended-hint")
    refute has_element?(lv, "#clock-starts-#{member.id}")
  end

  test "Last attended shows without a filter and sorts with never attended first (#367)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    old = activity_fixture(team, %{started_at: ~U[2026-01-10 18:00:00Z]})
    recent = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), -3, :day)})

    deleted =
      activity_fixture(team, %{
        started_at: DateTime.add(DateTime.utc_now(), -1, :day),
        deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    drifting = member_fixture(team, %{name: "Aaron Drifting"})
    attendance_fixture(old, drifting)
    attendance_fixture(deleted, drifting)
    seen = member_fixture(team, %{name: "Bea Seen"})
    attendance_fixture(recent, seen)
    never = member_fixture(team, %{name: "Cy Never"})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members")

    assert has_element?(lv, "#last-attended-#{drifting.id}", "Jan 10, 2026")
    assert has_element?(lv, "#last-attended-#{never.id}", "Never")

    {:ok, _lv, html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?sort=attended")

    assert names_in_order(html, [never.name, drifting.name, seen.name])

    {:ok, _lv, html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?sort=attended-")

    assert names_in_order(html, [seen.name, drifting.name, never.name])
  end

  test "a sign-up for a coming activity isn't attended: no last attended, no count (#364)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    now = DateTime.truncate(DateTime.utc_now(), :second)
    coming = activity_fixture(team, %{started_at: DateTime.add(now, 7, :day)})
    member = member_fixture(team, %{name: "Aaron Signed Up"})
    attendance_fixture(coming, member, %{started_at: coming.started_at})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?when=all")

    assert has_element?(lv, "#last-attended-#{member.id}", "Never")
    refute has_element?(lv, "#member_collection tr", "1 hour")
  end

  test "a rolling Period counts activities in it and lists members on the team in it (#367)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    now = DateTime.truncate(DateTime.utc_now(), :second)
    recent = activity_fixture(team, %{started_at: DateTime.add(now, -10, :day)})
    old = activity_fixture(team, %{started_at: DateTime.add(now, -120, :day)})
    joined = ~U[2024-01-01 00:00:00Z]

    busy = member_fixture(team, %{name: "Aaron Busy", joined_at: joined})
    attendance_fixture(recent, busy, %{started_at: recent.started_at})
    attendance_fixture(old, busy, %{started_at: old.started_at})
    quiet = member_fixture(team, %{name: "Bea Quiet", joined_at: joined})
    attendance_fixture(old, quiet, %{started_at: old.started_at})

    left_long_ago =
      member_fixture(team, %{
        name: "Cy Retired",
        joined_at: joined,
        left_at: DateTime.add(now, -200, :day)
      })

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members?when=90d&standing=all&sort=activities")

    assert html =~ busy.name
    assert html =~ quiet.name
    refute html =~ left_long_ago.name
    assert names_in_order(html, [quiet.name, busy.name])

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?when=90d")

    assert has_element?(lv, "#member_filter_form select[name='form[when]'] option[value='90d']")
    assert has_element?(lv, "#member_filter_form .filter-menu.is-on", "Period")
  end

  test "an old year link still opens that year (#367)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{joined_at: ~U[2024-01-01 00:00:00Z]})
    activity = activity_fixture(team, %{started_at: ~U[2025-03-10 18:00:00Z]})
    attendance_fixture(activity, member, %{started_at: activity.started_at})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?when=2025")

    assert has_element?(
             lv,
             "#member_filter_form select[name='form[when]'] option[selected][value='2025']"
           )
  end

  test "the Standing column shows only once a current member is not active, under any filter",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member_fixture(team)
    member_fixture(team, %{left_at: ~U[2025-06-01 00:00:00Z]})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members")

    assert has_element?(lv, "#member-view-current[aria-current=page]")
    refute has_element?(lv, "table th", "Standing")

    # A filter changes the rows, not the columns.
    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?standing=retired")

    refute has_element?(lv, "table th", "Standing")

    member_fixture(team, %{not_a_person: true})
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members")

    assert has_element?(lv, "table th", "Standing")
  end

  test "Standing: Not retired leaves out retired members; Retired and All show them",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    current = member_fixture(team, %{name: "Cara Current"})
    left = member_fixture(team, %{name: "Lee Left", left_at: ~U[2025-06-01 00:00:00Z]})
    retired = member_fixture(team, %{name: "Rae Retired", d4h_status: "RETIRED"})
    # Not a person, so the team has a current member who isn't active and shows Standing.
    leaving =
      member_fixture(team, %{
        not_a_person: true,
        left_at: DateTime.add(DateTime.utc_now(), 30, :day)
      })

    gone_bot = member_fixture(team, %{not_a_person: true, left_at: ~U[2025-06-01 00:00:00Z]})
    everyone = [current, left, retired, leaving, gone_bot]

    for {standing, shown} <- [
          {"current", [current, leaving]},
          {"retired", [left, retired, gone_bot]},
          {"not_a_person", [leaving]},
          {"all", everyone}
        ] do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/teams/#{team}/members?when=all&standing=#{standing}")

      for member <- everyone do
        assert has_element?(lv, "#last-attended-#{member.id}") == member in shown
      end

      assert has_element?(lv, "table th", "Retired") == standing in ["retired", "all"]
    end

    {:ok, lv, _html} = live(conn |> log_in_user(user), ~p"/teams/#{team}/members")
    assert has_element?(lv, "#member-view-current[aria-current=page]", "Not retired")

    {:ok, lv, _html} =
      live(conn |> log_in_user(user), ~p"/teams/#{team}/members?when=all&standing=all")

    assert has_element?(lv, "#standing-#{left.id}", "Retired")
    assert has_element?(lv, "#standing-#{gone_bot.id}", "Retired")
    assert has_element?(lv, "#standing-#{current.id}", "Active")
    assert has_element?(lv, "#standing-#{leaving.id}", "Not a person")

    {:ok, _lv, html} =
      live(
        conn |> log_in_user(user),
        ~p"/teams/#{team}/members?when=all&standing=all&sort=standing"
      )

    assert names_in_order(html, [current.name, left.name])
    assert names_in_order(html, [current.name, retired.name])
  end

  test "the Standing switch counts each standing and has no All (#469)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member_fixture(team, %{name: "Cara Current"})
    member_fixture(team, %{name: "Nico Bot", not_a_person: true})
    member_fixture(team, %{name: "Rae Retired", left_at: ~U[2025-06-01 00:00:00Z]})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?when=all&q=cara")

    # The logged-in user is an active member too.
    assert has_element?(lv, "#member-view-current", "3")
    assert has_element?(lv, "#member-view-active", "2")
    assert has_element?(lv, "#member-view-not_a_person", "1")
    assert has_element?(lv, "#member-view-retired", "1")
    refute has_element?(lv, "#member-view-all")
    refute has_element?(lv, "select[name='form[standing]']")
    assert has_element?(lv, "#member_filter_form-summary strong", "1 member")
  end

  test "a search that finds no one offers all members, and All shows as a menu (#469)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member_fixture(team, %{name: "Rae Retired", left_at: ~U[2025-06-01 00:00:00Z]})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?when=all&q=rae")

    lv |> element("#no-matching-members a", "Search all members") |> render_click()
    assert assert_patch(lv) =~ "standing=all"
    assert has_element?(lv, "td", "Rae Retired")
    refute has_element?(lv, "#member-switch [aria-current]")
    assert has_element?(lv, "select[name='form[standing]'] option[selected]", "All")
  end

  test "the Standing filter keeps active, away, or not a person members (#367)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    today = Service.Period.today(DateTime.utc_now(), team.timezone)
    active = member_fixture(team, %{name: "Aaron Active"})
    away = member_fixture(team, %{name: "Bea Away"})
    away_period_fixture(away, Date.add(today, -3), Date.add(today, 30))
    back = member_fixture(team, %{name: "Cy Back"})
    away_period_fixture(back, Date.add(today, -60), Date.add(today, -1))
    bot = member_fixture(team, %{name: "Door Bot", not_a_person: true})

    other_team = team_fixture()
    other_away = member_fixture(other_team)
    away_period_fixture(other_away, Date.add(today, -3), Date.add(today, 30))

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members")

    assert has_element?(lv, "#standing-#{active.id}", "Active")
    assert has_element?(lv, "#standing-#{back.id}", "Active")
    assert has_element?(lv, "#standing-#{bot.id}", "Not a person")
    until = today |> Date.add(30) |> Service.Format.day_in_year(today)
    assert has_element?(lv, "#standing-#{away.id}", "Away until #{until}")

    for {standing, shown} <- [
          {"active", [active, back]},
          {"away", [away]},
          {"not_a_person", [bot]}
        ] do
      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?standing=#{standing}")

      for member <- [active, away, back, bot] do
        assert has_element?(lv, "#standing-#{member.id}") == member in shown
      end
    end

    {:ok, _lv, html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?sort=standing")

    assert names_in_order(html, [away.name, bot.name])
  end

  test "the Standing sort puts not a person with the others, even with an away period",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    today = Service.Period.today(DateTime.utc_now(), team.timezone)
    away = member_fixture(team, %{name: "Bea Away"})
    away_period_fixture(away, Date.add(today, -3), Date.add(today, 30))
    # Marked after an away period was added: not a person still wins.
    bot = member_fixture(team, %{name: "Ann Bot", not_a_person: true})
    away_period_fixture(bot, Date.add(today, -3), Date.add(today, 5))
    member_fixture(team, %{name: "Cy Active"})

    {:ok, _lv, html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?sort=standing")

    assert names_in_order(html, [away.name, bot.name, "Cy Active"])
  end

  test "the Standing filter takes several standings from the attendance check (#366)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    today = Service.Period.today(DateTime.utc_now(), team.timezone)
    active = member_fixture(team)
    away = member_fixture(team)
    away_period_fixture(away, Date.add(today, -3), Date.add(today, 30))
    bot = member_fixture(team, %{not_a_person: true})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?standing=active,away")

    assert has_element?(lv, "select[name='form[standing]'] option[selected]", "Active or away")
    assert has_element?(lv, "#standing-#{active.id}")
    assert has_element?(lv, "#standing-#{away.id}")
    refute has_element?(lv, "#standing-#{bot.id}")

    assert_raise Web.Status.NotFound, fn ->
      live(log_in_user(conn, user), ~p"/teams/#{team}/members?standing=active,gone")
    end
  end

  test "less common filters wait behind More filters until one is on", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members")

    assert has_element?(lv, "#member_filter_form-more", "More filters")
    assert has_element?(lv, ".filter-menu.is-more select[name='form[attended]']")
    refute has_element?(lv, ".filter-menu.is-more select[name='form[when]']")

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?attended=90")

    refute has_element?(lv, ".filter-menu.is-more select[name='form[attended]']")
    assert has_element?(lv, ".filter-menu.is-on select[name='form[attended]']")
  end

  defp names_in_order(html, names) do
    positions = Enum.map(names, &elem(:binary.match(html, &1), 0))
    positions == Enum.sort(positions)
  end

  # Away periods are often leave, and check-ins and missing details are team admins' own
  # lists: a member's list never filters, counts, sorts, or labels by them (#440).
  describe "for a member" do
    setup %{conn: conn} do
      %{team: team, user: user, member: member} = member_with_login_fixture()
      today = Date.utc_today()
      away = member_fixture(team, %{name: "Avery Away", phone: nil})
      away_period_fixture(away, Date.add(today, -5), Date.add(today, 30))
      bot = member_fixture(team, %{name: "Nico Bot", not_a_person: true})
      member_fixture(team, %{name: "Rae Retired", left_at: ~U[2025-06-01 00:00:00Z]})
      %{conn: log_in_user(conn, user), team: team, member: member, away: away, bot: bot}
    end

    test "the roster with Not retired, Not a person, and Retired, and no team admin filters",
         %{conn: conn, team: team, away: away, bot: bot} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members?when=all")

      assert has_element?(lv, "td", "Avery Away")
      assert has_element?(lv, "td", "Nico Bot")
      assert has_element?(lv, "#member-view-current", "3")
      assert has_element?(lv, "#member-view-retired", "1")
      refute has_element?(lv, "#member-view-active")
      refute has_element?(lv, "#member-view-away")
      assert has_element?(lv, "#member-view-not_a_person", "1")
      refute has_element?(lv, "select[name='form[details]']")
      refute has_element?(lv, "select[name='form[attended]']")
      refute has_element?(lv, "#member-add")
      refute render(lv) =~ "Away until"

      # Away reads Active to a member: it's often leave.
      assert has_element?(lv, "#standing-#{bot.id}", "Not a person")
      assert has_element?(lv, "#standing-#{away.id}", "Active")
      refute has_element?(lv, ~s{th a[href*="sort=standing"]})
    end

    test "no Standing column when nobody is Not a person", %{conn: conn, team: team, bot: bot} do
      bot |> Ecto.Changeset.change(not_a_person: false) |> App.Repo.update!()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members?when=all")

      refute has_element?(lv, "th", "Standing")
    end

    test "ignores the URL's standings, Attended, Details, and Standing sort",
         %{conn: conn, team: team} do
      for params <- [
            "standing=away",
            "standing=active",
            "standing=active,away",
            "attended=30",
            "details=missing",
            "sort=standing"
          ] do
        {:ok, lv, _html} = live(conn, "/teams/#{team.subdomain}/members?when=all&#{params}")

        assert has_element?(lv, "#member-view-current[aria-current]"), params
        assert has_element?(lv, "td", "Avery Away"), params
        assert has_element?(lv, "td", "Nico Bot"), params
        refute has_element?(lv, "#attended-hint"), params
        refute has_element?(lv, "th", "Missing"), params
      end
    end

    test "Not a person filters to bot accounts", %{conn: conn, team: team, away: away} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members?when=all&standing=not_a_person")

      assert has_element?(lv, "#member-view-not_a_person[aria-current]")
      assert has_element?(lv, "td", "Nico Bot")
      refute has_element?(lv, "td", away.name)
    end

    test "All shows retired members, with the Standing menu", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members?when=all&standing=all")

      assert has_element?(lv, "td", "Rae Retired")
      assert has_element?(lv, "th", "Retired")

      for {value, shown?} <- [current: true, retired: true, all: true, active: false, away: false] do
        assert has_element?(lv, "select[name='form[standing]'] option[value=#{value}]") == shown?
      end
    end
  end
end
