defmodule Web.TeamDashboardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AttendanceStub
  alias App.Model.AttendanceScan
  alias App.Model.Team
  alias App.Repo

  defp open(conn, user, team), do: conn |> log_in_user(user) |> live(~p"/teams/#{team}")

  defp hours_from_now(hours),
    do: DateTime.utc_now() |> DateTime.add(hours, :hour) |> DateTime.truncate(:second)

  defp at(hours, attrs) do
    started_at = hours_from_now(hours)
    Map.merge(%{started_at: started_at, finished_at: DateTime.add(started_at, 2, :hour)}, attrs)
  end

  test "attendance nobody sent opens the activity's Attendance page (#475)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity = activity_fixture(team, at(-24, %{title: "Training night"}))

    AttendanceScan.insert!(%AttendanceScan{
      team_id: team.id,
      activity_id: activity.id,
      member_id: member_fixture(team).id,
      kind: "arrived",
      method: "name",
      scanned_at: DateTime.utc_now()
    })

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#attention-attendance_to_send", "Attendance to send: Training night")

    assert has_element?(
             lv,
             ~s{#attention-attendance_to_send a[href="/teams/#{team.subdomain}/activities/#{activity.id}/attendance"]}
           )
  end

  test "renders team dashboard", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} = open(conn, user, team)

    assert html =~ team.name
  end

  test "shows the team's initials until it saves a logo", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, team} = Team.update(team, %{name: "Coast Range SAR"})

    {:ok, lv, _html} = open(conn, user, team)
    refute has_element?(lv, "#team-logo")
    assert has_element?(lv, "#team-initials", "CR")

    team_logo_fixture(team)

    {:ok, lv, _html} = open(conn, user, team)
    assert has_element?(lv, "#team-logo")
  end

  test "a failed refresh needs attention and says why", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, team} =
      Team.update(team, %{
        d4h_refresh_result: "Error: No access key. Save one in team settings."
      })

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#attention-refresh", "No access key. Save one in team settings.")
  end

  test "Refresh now goes while a refresh runs", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = open(conn, user, team)
    assert has_element?(lv, "#d4h-updated")
    assert has_element?(lv, "#refresh-now")

    {:ok, team} = Team.update(team, %{d4h_refresh_result: "Refreshing"})
    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#refreshing", "Refreshing…")
    refute has_element?(lv, "#d4h-updated")
    refute has_element?(lv, "#refresh-now")
  end

  test "Open in D4H sits in the line under the team's name", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = open(conn, user, team)
    assert has_element?(lv, "#team-head-facts #open-d4h[target=_blank]", "Open in D4H")
  end

  test "an empty team has nothing coming up and nothing to do", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = open(conn, user, team)

    refute has_element?(lv, "#next-up")
    assert has_element?(lv, "#coming-up-empty")
    assert has_element?(lv, "#needs-attention-empty")
  end

  test "the activity starting soon is NextUp, with the page's take attendance button",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    soon = activity_fixture(team, at(3, %{title: "Rope rescue"}))
    later = activity_fixture(team, at(72, %{title: "Night navigation"}))
    activity_fixture(team, at(24 * 20, %{title: "Too far off"}))
    activity_fixture(team_fixture(), at(2, %{title: "Another team's"}))

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#next-up", "Rope rescue")

    assert has_element?(
             lv,
             ~s{#next-up-take-attendance[href="/teams/#{team.subdomain}/activities/#{soon.id}/take-attendance"]}
           )

    assert has_element?(
             lv,
             ~s{#coming-up-#{later.id} a[href="/teams/#{team.subdomain}/activities/#{later.id}"]},
             "Night navigation"
           )

    refute has_element?(lv, "#coming-up-#{soon.id}")
    refute has_element?(lv, "#coming-up-list", "Too far off")
    refute has_element?(lv, "#next-up", "Another team's")
  end

  test "waiting chores need attention, with member logins on", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    category = chore_category_fixture(team)
    chore_fixture(member_fixture(team), category)

    {:ok, lv, _html} = open(conn, user, team)
    refute has_element?(lv, "#attention-chores")

    team |> Ecto.Changeset.change(member_logins: true, chores_enabled: true) |> Repo.update!()
    {:ok, lv, _html} = open(conn, user, team)
    assert has_element?(lv, "#attention-chores", "1 chore to accept")
    assert has_element?(lv, ~s{#attention-chores a[href="/teams/#{team.subdomain}/chores"]})
  end

  test "a team admin's own chores need another team admin, unless there is none (#698)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    team =
      team |> Ecto.Changeset.change(member_logins: true, chores_enabled: true) |> Repo.update!()

    category = chore_category_fixture(team)
    me = Repo.get_by!(App.Model.Member, team_id: team.id, email: user.email)
    chore_fixture(me, category)
    chore_fixture(me, category)

    # Nobody else can accept them.
    {:ok, lv, _html} = open(conn, user, team)
    assert has_element?(lv, "#attention-chores", "2 chores to accept")

    other = manager_fixture(team)
    {:ok, lv, _html} = open(conn, user, team)
    refute has_element?(lv, "#attention-chores")

    chore_fixture(member_fixture(team), category)
    {:ok, lv, _html} = open(conn, user, team)
    assert has_element?(lv, "#attention-chores", "1 chore to accept")

    # The other team admin sees them all.
    other_user = App.AccountsFixtures.user_fixture(%{email: other.email})
    {:ok, lv, _html} = open(conn, other_user, team)
    assert has_element?(lv, "#attention-chores", "3 chores to accept")
  end

  test "a team admin's own certificates need another team admin, unless there is none",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    team =
      team
      |> Ecto.Changeset.change(member_logins: true, certificates_enabled: true)
      |> Repo.update!()

    qualification = qualification_fixture(team)
    me = Repo.get_by!(App.Model.Member, team_id: team.id, email: user.email)
    certificate_fixture(me, qualification)

    # Nobody else can accept it.
    {:ok, lv, _html} = open(conn, user, team)
    assert has_element?(lv, "#attention-certificates", "1 certificate to accept")

    other = manager_fixture(team)
    {:ok, lv, _html} = open(conn, user, team)
    refute has_element?(lv, "#attention-certificates")

    certificate_fixture(member_fixture(team), qualification)
    {:ok, lv, _html} = open(conn, user, team)
    assert has_element?(lv, "#attention-certificates", "1 certificate to accept")

    # The other team admin sees them all.
    other_user = App.AccountsFixtures.user_fixture(%{email: other.email})
    {:ok, lv, _html} = open(conn, other_user, team)
    assert has_element?(lv, "#attention-certificates", "2 certificates to accept")
  end

  test "this team's drafts and members missing details need attention", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, at(-48, %{is_published: false}))
    activity_fixture(team, at(-48, %{is_published: true}))
    # Drafts from before the last 30 days are left alone.
    activity_fixture(team, at(-24 * 40, %{is_published: false}))
    member_fixture(team, %{phone: nil})
    member_fixture(team, %{email: nil})
    member_fixture(team, %{address: nil})
    member_fixture(team, %{phone: nil, left_at: ~U[2025-01-01 00:00:00Z]})
    member_fixture(team, %{phone: nil, email: nil, not_a_person: true})

    other = team_fixture()
    activity_fixture(other, at(-48, %{is_published: false}))
    member_fixture(other, %{email: nil})

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#attention-drafts", "1 draft activity")

    assert has_element?(
             lv,
             ~s{#attention-drafts a[href="/teams/#{team.subdomain}/activities?status=draft&when=recent&sort=date-"]}
           )

    assert has_element?(
             lv,
             "#attention-missing_details",
             "3 members have no email, mobile phone, or address"
           )

    assert has_element?(
             lv,
             ~s{#attention-missing_details a[href="/teams/#{team.subdomain}/members?details=missing"]}
           )
  end

  test "members who have not attended link to the members page in the team's time frame",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    team = team |> Ecto.Changeset.change(not_seen_days: 180) |> App.Repo.update!()
    member_fixture(team, %{joined_at: ~U[2024-01-01 00:00:00Z]})

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(
             lv,
             "#attention-not_seen",
             "1 member has not attended an activity in 180 days"
           )

    assert has_element?(
             lv,
             ~s{#attention-not_seen a[href="/teams/#{team.subdomain}/members?attended=180&standing=active"]}
           )
  end

  test "the attendance check's count matches the Members list it links to (#366)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    callout = group_fixture(team, %{title: "Callout"})
    joined = ~U[2024-01-01 00:00:00Z]

    team =
      team
      |> Ecto.Changeset.change(watch_d4h_group_id: callout.d4h_group_id)
      |> App.Repo.update!()

    today = Service.Period.today(DateTime.utc_now(), team.timezone)
    drifting = member_fixture(team, %{name: "Drifting", joined_at: joined})
    group_member_fixture(callout, drifting)
    away = member_fixture(team, %{name: "Away Now", joined_at: joined})
    group_member_fixture(callout, away)
    away_period_fixture(away, Date.add(today, -100), Date.add(today, -1))
    bot = member_fixture(team, %{name: "Bot", joined_at: joined, not_a_person: true})
    group_member_fixture(callout, bot)
    _not_in_group = member_fixture(team, %{joined_at: joined})

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(
             lv,
             "#attention-not_seen",
             "1 member of Callout has not attended an activity in 90 days"
           )

    path = "/teams/#{team.subdomain}/members?attended=90&group=#{callout.id}&standing=active"
    assert has_element?(lv, ~s{#attention-not_seen a[href="#{path}"]})

    {:ok, list, _html} = live(log_in_user(conn, user), path)
    assert has_element?(list, "#member-view-active[aria-current=page]", "1")
    assert has_element?(list, "#clock-starts-#{drifting.id}", "Joined")
    refute has_element?(list, "#clock-starts-#{away.id}")
  end

  test "a watched group gone from D4H warns and links to settings (#366)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    team = team |> Ecto.Changeset.change(watch_d4h_group_id: 424_242) |> App.Repo.update!()

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#attention-watch_missing", "The group you watch was deleted")

    assert has_element?(
             lv,
             ~s{#attention-watch_missing a[href="/teams/#{team.subdomain}/settings/members"]}
           )
  end

  test "a team admin snoozes the drafts, and the rest stay (#751)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, at(-48, %{is_published: false}))
    member_fixture(team, %{phone: nil})
    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#snooze-missing_details")
    lv |> element("#snooze-drafts") |> render_click(%{"choice" => "day"})

    refute has_element?(lv, "#attention-drafts")
    assert has_element?(lv, "#snoozed-drafts", "1 draft activity")
    assert has_element?(lv, "#attention-missing_details")
  end

  test "Check activities lists the same drafts the dashboard counts", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, at(-48, %{title: "Counted draft", is_published: false}))
    activity_fixture(team, at(-24 * 40, %{title: "Old draft", is_published: false}))
    activity_fixture(team, at(-1, %{title: "Running draft", is_published: false}))
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
    assert has_element?(lv, "#attention-drafts", "1 draft activity")

    {:ok, list, _html} =
      lv |> element("#attention-drafts a") |> render_click() |> follow_redirect(conn)

    assert has_element?(list, "#activity_collection", "Counted draft")
    refute has_element?(list, "#activity_collection", "Old draft")
    refute has_element?(list, "#activity_collection", "Running draft")
  end

  test "published activities with no hours tag need attention, and the link lists them",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    year = DateTime.now!(team.timezone).year
    {:ok, june} = year |> Date.new!(6, 15) |> DateTime.new(~T[18:00:00])
    june = %{started_at: june, finished_at: DateTime.add(june, 2, :hour), is_published: true}

    tag_fixture(team, "Primary Hours")
    team |> Ecto.Changeset.change(other_hours_tag: "Social") |> Repo.update!()
    activity_fixture(team, Map.merge(june, %{title: "Untagged", tags: ["Training"]}))
    no_tags = activity_fixture(team, Map.merge(june, %{title: "No tags", tags: nil}))
    activity_fixture(team, Map.merge(june, %{title: "Primary", tags: ["Primary Hours"]}))
    activity_fixture(team, Map.merge(june, %{title: "BBQ", tags: ["Social"]}))
    activity_fixture(team, Map.merge(june, %{title: "Draft", tags: [], is_published: false}))
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
    assert has_element?(lv, "#attention-untagged", "2 activities in #{year} have no hours tag")

    assert has_element?(lv, "#attention-untagged", "Set each one's hours tag in D4H.")

    {:ok, list, _html} =
      lv |> element("#attention-untagged a") |> render_click() |> follow_redirect(conn)

    assert has_element?(list, "#activity_collection", "Untagged")
    assert has_element?(list, "#activity_collection", "No tags")
    assert has_element?(list, "#activity-#{no_tags.id}-tags-locked a", "Change activity")
    refute has_element?(list, "#activity_collection", "Primary")
    refute has_element?(list, "#activity_collection", "BBQ")
    refute has_element?(list, "#activity_collection", "Draft")
  end

  test "activities with two hours tags need attention, and the link lists them (#763)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    year = DateTime.now!(team.timezone).year
    {:ok, june} = year |> Date.new!(6, 15) |> DateTime.new(~T[18:00:00])
    june = %{started_at: june, finished_at: DateTime.add(june, 2, :hour), is_published: true}

    team |> Ecto.Changeset.change(other_hours_tag: "Social") |> Repo.update!()

    both =
      activity_fixture(team, Map.merge(june, %{title: "Both", tags: ["Primary Hours", "Social"]}))

    activity_fixture(
      team,
      Map.merge(june, %{
        title: "Draft both",
        tags: ["Secondary Hours", "Social"],
        is_published: false
      })
    )

    activity_fixture(team, Map.merge(june, %{title: "One tag", tags: ["Primary Hours", "Rope"]}))
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

    assert has_element?(
             lv,
             "#attention-two_hours_tags",
             "2 activities in #{year} have two hours tags"
           )

    assert has_element?(
             lv,
             "#attention-two_hours_tags",
             "count primary hours for 1 and secondary hours for 1."
           )

    {:ok, list, _html} =
      lv |> element("#attention-two_hours_tags a") |> render_click() |> follow_redirect(conn)

    assert has_element?(list, "#activity_collection", "Both")
    assert has_element?(list, "#activity_collection", "Draft both")
    assert has_element?(list, "#activity-#{both.id}-tags-locked", "change its tags")
    refute has_element?(list, "#activity_collection", "One tag")
  end

  test "a team that does not use the hours tags is not told about them", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, %{tags: [], is_published: true})

    {:ok, lv, _html} = open(conn, user, team)
    refute has_element?(lv, "#attention-untagged")
  end

  test "a qualification running out needs attention", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team)

    qualification_award_fixture(qualification, member_fixture(team), %{
      ends_at: hours_from_now(24 * 10)
    })

    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#attention-expiring", "1 award expires within 60 days")
  end

  test "the team's year loads after the rest of the page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, at(-24 * 5, %{activity_kind: "incident"}))

    {:ok, lv, _html} = open(conn, user, team)

    assert render_async(lv) =~ "Activities by month"
    assert has_element?(lv, "#stat-incidents", "1")
    assert has_element?(lv, "#activity-calendar")
  end

  describe "for a member" do
    setup %{conn: conn} do
      %{team: team, member: member, user: user} = member_with_login_fixture()
      %{conn: log_in_user(conn, user), team: team, member: member, user: user}
    end

    test "Next up has Take attendance once its window opens", %{conn: conn, team: team} do
      soon = activity_fixture(team, at(1, %{title: "Rope practice"}))
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      assert has_element?(
               lv,
               ~s{#next-up-take-attendance[href="/teams/#{team.subdomain}/activities/#{soon.id}/take-attendance"]}
             )
    end

    test "is the team admin's page without the controls: no Refresh now, Needs attention, or Take attendance",
         %{conn: conn, team: team} do
      # Members take attendance from 2 hours before the start (#475).
      activity_fixture(team, at(3, %{title: "Rope practice"}))
      activity_fixture(team, at(72, %{title: "Swiftwater"}))
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      assert has_element?(lv, "#d4h-updated")
      assert has_element?(lv, "#open-d4h", "Open in D4H")
      refute has_element?(lv, "#refresh-now")
      refute has_element?(lv, "#needs-attention")
      assert has_element?(lv, "#next-up", "Rope practice")
      refute has_element?(lv, "#next-up-take-attendance")
      assert has_element?(lv, "#coming-up", "Swiftwater")
      refute has_element?(lv, "#coming-up", "Rope practice")
      assert has_element?(lv, "#to-do-empty")
      assert has_element?(lv, "#side-nav-dashboard[aria-current=page]")
      refute has_element?(lv, "#side-nav-groups")
      assert has_element?(lv, ~s{#stat-members a[href="/teams/#{team.subdomain}/members"]})
    end

    test "Coming up links to each activity's page from its title", %{conn: conn, team: team} do
      activity = activity_fixture(team, at(30, %{title: "Rope practice"}))
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      assert has_element?(
               lv,
               ~s{#coming-up-#{activity.id} a[href="/teams/#{team.subdomain}/activities/#{activity.id}"]},
               "Rope practice"
             )

      refute has_element?(lv, "#coming-up-list .row-link")
    end

    test "Next up counts who signed up, and the member replies from it",
         %{conn: conn, team: team, member: member} do
      team = team |> Ecto.Changeset.change(d4h_access_key: "team-key") |> Repo.update!()
      activity = activity_fixture(team, at(3, %{title: "Rope practice"}))
      row = attendance_fixture(activity, member, %{status: "requested"})
      attendance_fixture(activity, member_fixture(team), %{status: "attending"})
      AttendanceStub.stub([row])

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      assert has_element?(lv, "#next-up-hint", "123 Main St · in ")
      assert has_element?(lv, "#next-up-hint", " · 1 signed up")

      lv |> element("#next-up-reply-yes") |> render_click()

      assert_received {:d4h_write, _id, %{"status" => "ATTENDING"}}
      assert has_element?(lv, "#next-up-reply-state", "Signed up")
      assert has_element?(lv, "#next-up-reply-calendar", "Add to calendar")
      assert has_element?(lv, "#next-up-hint", " · 2 signed up")
    end

    test "Coming up holds the small reply buttons, or the reply and Change",
         %{conn: conn, team: team, member: member} do
      asked = activity_fixture(team, at(30, %{title: "Rope practice"}))
      answered = activity_fixture(team, at(50, %{title: "Swiftwater"}))
      not_invited = activity_fixture(team, at(70, %{title: "Annual general meeting"}))
      attendance_fixture(asked, member, %{status: "requested"})
      attendance_fixture(answered, member, %{status: "absent"})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      assert has_element?(lv, "#coming-up-reply-#{asked.id}-yes.btn-sm", "I'll be there")
      assert has_element?(lv, "#coming-up-reply-#{asked.id}-no.btn-sm", "Can't make it")
      assert has_element?(lv, "#coming-up-reply-#{answered.id}-state", "Can't make it")
      assert has_element?(lv, "#coming-up-reply-#{answered.id}-change", "Change")
      refute has_element?(lv, "#coming-up-reply-#{answered.id}-calendar")
      refute has_element?(lv, "#coming-up-#{not_invited.id} .reply")
      refute has_element?(lv, "#coming-up header", "reply")
    end

    test "a team admin viewing as the member replies to nothing", %{team: team, member: member} do
      admin = App.AccountsFixtures.user_fixture()
      manager_fixture(team, %{email: admin.email})
      activity = activity_fixture(team, at(30, %{title: "Rope practice"}))
      attendance_fixture(activity, member, %{status: "requested"})

      conn = build_conn() |> log_in_user(admin)
      conn = post(conn, ~p"/teams/#{team}/members/#{member}/view-as")
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      lv |> element("#coming-up-reply-#{activity.id}-yes") |> render_click()

      assert has_element?(lv, "#flash-error", "so nothing is saved")
      assert has_element?(lv, "#coming-up-reply-#{activity.id}-yes")
    end

    test "a refresh event from a member does nothing", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      render_hook(lv, "refresh", %{})
      refute has_element?(lv, "#refreshing")
    end

    test "For you to do: the ID card leaves once it is in Wallet",
         %{conn: conn, team: team, member: member} do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      assert has_element?(lv, "#to-do-card")

      card |> Ecto.Changeset.change(in_wallet_at: DateTime.utc_now()) |> Repo.update!()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      refute has_element?(lv, "#to-do-card")
    end

    test "For you to do: no ID card while the team has ID cards off",
         %{conn: conn, team: team, member: member} do
      team |> Ecto.Changeset.change(id_cards_enabled: false) |> Repo.update!()
      member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      refute has_element?(lv, "#to-do-card")
    end

    # MemberToDo's tests cover the season with a fixed date; this checks the page reads
    # today's.
    test "For you to do: a new letter in letter season, until the member downloads it",
         %{conn: conn, team: team, member: member} do
      %{year: year} = this_year_fixture(team)
      letter = tax_credit_letter_fixture(member, %{year: year - 1})
      in_season? = Service.Period.letter_season?(DateTime.utc_now(), team.timezone)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      assert has_element?(lv, "#to-do-letter", "Your #{year - 1} tax credit letter is ready") ==
               in_season?

      conn |> get(~p"/teams/#{team}/me/tax-credit-letters/#{letter.id}/pdf") |> response(200)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      refute has_element?(lv, "#to-do-letter")
    end

    test "For you to do: a declined chore, until the member deletes it",
         %{conn: conn, team: team, member: member} do
      category = chore_category_fixture(team)

      chore_fixture(member, category, %{
        status: :declined,
        description: "Slept at the hall",
        decline_reason: "Not a chore.",
        decided_at: DateTime.utc_now()
      })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      assert has_element?(lv, "#to-do-declined-chores", "Your chore was declined")
      assert has_element?(lv, "#to-do-declined-chores", "Slept at the hall")
    end

    test "For you to do: a qualification expiring within 60 days",
         %{conn: conn, team: team, member: member} do
      first_aid = qualification_fixture(team, %{title: "First Aid"})
      ends_at = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
      qualification_award_fixture(first_aid, member, %{ends_at: ends_at})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      form = ~p"/teams/#{team}/certificates/new?#{[qualification: first_aid.id]}"

      assert has_element?(
               lv,
               ~s{#to-do-qualification-#{first_aid.id} a[href="#{form}"]},
               "Your First Aid expires in 30 days"
             )

      assert has_element?(lv, "#to-do-qualification-#{first_aid.id}", "Add the new certificate.")

      # A certificate for it waiting takes it off; declined, the certificate is the item.
      certificate = certificate_fixture(member, first_aid)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      refute has_element?(lv, "#to-do-qualification-#{first_aid.id}")

      certificate
      |> Ecto.Changeset.change(status: :declined, decline_reason: "Blurry")
      |> Repo.update!()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      assert has_element?(lv, "#to-do-declined-certificates", "Your certificate was declined")

      # With certificates off, it opens Your membership, as before.
      team |> Ecto.Changeset.change(certificates_enabled: false) |> Repo.update!()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      assert has_element?(
               lv,
               ~s{#to-do-qualification-#{first_aid.id} a[href="/teams/#{team.subdomain}/me"]}
             )
    end
  end

  test "a team admin who is a member gets both Needs attention and For you to do",
       %{conn: conn} do
    %{team: team, user: user} = member_with_login_fixture(%{d4h_permission: 0})
    {:ok, lv, _html} = open(conn, user, team)

    assert has_element?(lv, "#needs-attention")
    assert has_element?(lv, "#to-do")
    assert has_element?(lv, "#refresh-now")
  end

  describe "the whiteboard strip (#515)" do
    test "a member reads the Important notes, at most 2, and a link to the rest", %{conn: conn} do
      %{team: team, user: user} = member_with_login_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      refute has_element?(lv, "#whiteboard")

      plain = whiteboard_note_fixture(team, %{text: "Dues are due by November 30."})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      assert has_element?(lv, "#whiteboard-note-#{plain.id}", "Dues are due")
      refute has_element?(lv, "#whiteboard-more")

      first =
        whiteboard_note_fixture(team, %{
          text: "Pager test Sunday.",
          important: true,
          d4h_created_at: ~U[2026-10-20 00:00:00Z]
        })

      linked =
        whiteboard_note_fixture(team, %{
          text: "Winter tires go on.",
          important: true,
          url: "https://www.example.com/tires",
          d4h_created_at: ~U[2026-10-21 00:00:00Z]
        })

      third =
        whiteboard_note_fixture(team, %{
          text: "Oldest Important.",
          important: true,
          d4h_created_at: ~U[2026-10-01 00:00:00Z]
        })

      whiteboard_note_fixture(team, %{
        text: "Archived last week.",
        important: true,
        archived_at: DateTime.utc_now(:second) |> DateTime.add(-3, :day)
      })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      assert has_element?(lv, "#whiteboard-note-#{first.id}.is-important", "Important:")

      assert has_element?(
               lv,
               ~s{#whiteboard-note-#{linked.id} a[href="https://www.example.com/tires"]},
               "example.com"
             )

      refute has_element?(lv, "#whiteboard-note-#{third.id}")
      refute has_element?(lv, "#whiteboard-note-#{plain.id}")
      refute has_element?(lv, "#whiteboard", "Archived last week")

      assert has_element?(
               lv,
               ~s{#whiteboard-more[href="/teams/#{team.subdomain}/whiteboard"]},
               "2 more notes"
             )
    end

    test "an organization's note opens with who it is from", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      note = whiteboard_note_fixture(team, %{owner_kind: :organization})

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}")
      assert has_element?(lv, "#whiteboard-note-#{note.id}", "Your organization:")
    end

    test "a team admin sees no strip with no notes, nor with the module off", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      refute has_element?(lv, "#whiteboard")

      whiteboard_note_fixture(team)
      team |> Ecto.Changeset.change(whiteboard_enabled: false) |> Repo.update!()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      refute has_element?(lv, "#whiteboard")
    end
  end

  describe "Retiring members (#514)" do
    test "are left out of missing details and counted apart by the items they hold",
         %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      leavers = group_fixture(team, %{title: "Leavers"})

      team =
        team
        |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id)
        |> App.Repo.update!()

      holding = member_fixture(team, %{phone: nil})
      clear = member_fixture(team)
      gone = member_fixture(team, %{left_at: ~U[2025-01-01 00:00:00Z]})
      for member <- [holding, clear, gone], do: group_member_fixture(leavers, member)
      kit = equipment_item_fixture(team, %{member_id: holding.id})
      equipment_item_fixture(team, %{d4h_container_id: kit.d4h_equipment_id})

      {:ok, lv, _html} = open(conn, user, team)

      refute has_element?(lv, "#attention-missing_details")
      assert has_element?(lv, "#attention-retiring", "1 retiring member holds 2 items")
      assert has_element?(lv, "#attention-retiring_clear", "1 retiring member holds no items")
      assert has_element?(lv, "#attention-retiring_clear", "Retire them in D4H.")

      assert has_element?(
               lv,
               ~s{#attention-retiring a[href="/teams/#{team.subdomain}/equipment?place=retiring"]}
             )

      assert has_element?(
               lv,
               ~s{#attention-retiring_clear a[href="/teams/#{team.subdomain}/members?standing=retiring&items=none"]}
             )
    end

    test "a team admin snoozes the item for every team admin, and shows it again (#751)",
         %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      leavers = group_fixture(team, %{title: "Leavers"})

      team =
        team
        |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id)
        |> App.Repo.update!()

      holding = member_fixture(team)
      group_member_fixture(leavers, holding)
      equipment_item_fixture(team, %{member_id: holding.id})
      group_member_fixture(leavers, member_fixture(team, %{d4h_permission: 1}))

      {:ok, lv, _html} = open(conn, user, team)

      assert has_element?(lv, "#snooze-retiring[data-confirm-choice=week]")
      refute has_element?(lv, "#snooze-retiring_access")
      refute has_element?(lv, "#attention-snoozed")

      lv |> element("#snooze-retiring") |> render_click(%{"choice" => "week"})

      refute has_element?(lv, "#attention-retiring")
      assert has_element?(lv, "#attention-snoozed summary", "1 snoozed")
      assert has_element?(lv, "#snoozed-retiring", "1 retiring member holds 1 item")
      assert has_element?(lv, "#snoozed-retiring", "Snoozed by")

      # Every team admin sees it snoozed.
      {:ok, other, _html} = open(conn, user, team)
      refute has_element?(other, "#attention-retiring")

      lv |> element("#show-again-retiring") |> render_click()

      assert has_element?(lv, "#attention-retiring")
      refute has_element?(lv, "#attention-snoozed")
    end

    test "warns of retiring members D4H still lets log in", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      leavers = group_fixture(team, %{title: "Leavers"})

      team =
        team
        |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id)
        |> App.Repo.update!()

      for permission <- [1, 2, 4, nil],
          do: group_member_fixture(leavers, member_fixture(team, %{d4h_permission: permission}))

      member_fixture(team, %{d4h_permission: 2})

      {:ok, lv, _html} = open(conn, user, team)

      # Red, and above every warning, such as the attendance check's.
      assert has_element?(
               lv,
               "#needs-attention-list li:first-child#attention-retiring_access.is-danger",
               "2 retiring members can still log in to D4H"
             )

      assert has_element?(
               lv,
               "#attention-retiring_access",
               "Set their access to No access in D4H."
             )

      assert has_element?(
               lv,
               ~s{#attention-retiring_access a[href="/teams/#{team.subdomain}/members?standing=retiring&access=some"]}
             )
    end

    test "a deleted Retiring group warns and links to settings", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      team = team |> Ecto.Changeset.change(retiring_d4h_group_id: 424_242) |> App.Repo.update!()

      {:ok, lv, _html} = open(conn, user, team)

      assert has_element?(lv, "#attention-retiring_missing", "The Retiring group was deleted")

      assert has_element?(
               lv,
               ~s{#attention-retiring_missing a[href="/teams/#{team.subdomain}/settings/members"]}
             )
    end
  end
end
