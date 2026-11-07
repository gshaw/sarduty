defmodule Web.ActivityMembersLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias App.AttendanceStub
  alias App.Model.ActivityUpdate
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.Reminder
  alias App.Repo

  # A team admin changes attendance on the Members tab after the start (#766), with D4H
  # stubbed.
  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    starts = ~U[2026-10-28 02:00:00Z]

    activity =
      activity_fixture(team, %{
        title: "Swiftwater training",
        started_at: starts,
        finished_at: ~U[2026-10-28 04:30:00Z]
      })

    alex = member_fixture(team, %{name: "Alex Chen"})
    casey = member_fixture(team, %{name: "Casey Dhillon"})
    drew = member_fixture(team, %{name: "Drew Patel"})
    cameron = member_fixture(team, %{name: "Cameron Ruiz"})
    riley = member_fixture(team, %{name: "Riley Okafor"})

    rows = [
      attendance_fixture(activity, alex, %{status: "attending", started_at: starts}),
      attendance_fixture(activity, casey, %{
        status: "attending",
        started_at: starts,
        duration_in_minutes: 150
      }),
      attendance_fixture(activity, drew, %{status: "absent", started_at: starts}),
      attendance_fixture(activity, cameron, %{status: "requested", started_at: starts}),
      attendance_fixture(activity, riley, %{status: "requested", started_at: starts})
    ]

    %{
      conn: log_in_user(conn, user),
      team: team,
      activity: activity,
      rows: rows,
      alex: alex,
      casey: casey,
      drew: drew,
      cameron: cameron,
      riley: riley
    }
  end

  defp path(ctx), do: ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/members"

  defp check(lv, ids, change \\ nil) do
    params = %{"member_ids" => Enum.map(ids, &to_string/1)}
    params = if change, do: Map.put(params, "change", change), else: params
    lv |> form("#members-change-form") |> render_change(params)
  end

  test "a table for each attendance, then one list and one button (A)", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    assert has_element?(lv, "#members-table #member-row-#{ctx.alex.id}")
    assert has_element?(lv, "#members-table #member-row-#{ctx.drew.id}")
    assert has_element?(lv, "#members-table #member-row-#{ctx.riley.id}")
    assert has_element?(lv, "#members-table-select-all")
    assert has_element?(lv, ~s|label[for="members-select-#{ctx.casey.id}"]|, "Casey Dhillon")

    assert has_element?(lv, "#members-change legend", "For the checked members")
    assert has_element?(lv, "#members-change", "Mark attended")

    assert has_element?(
             lv,
             "#members-change",
             "Gives the checked the activity's times, 19:00 to 21:30."
           )

    assert has_element?(lv, "#members-change", "The checked who attended lose their hours.")

    assert has_element?(
             lv,
             "#members-change",
             "The checked get your message and a link to the activity."
           )

    assert has_element?(
             lv,
             "#members-change",
             "The checked come off the activity, and lose any hours."
           )

    assert has_element?(lv, "#members-change-send[disabled]", "Change members")
    assert has_element?(lv, "#members-add", "Add members")
    refute has_element?(lv, "#members-remove")
  end

  test "the button counts the members its change changes (V)", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    check(lv, [ctx.casey.id, ctx.cameron.id])
    assert has_element?(lv, "#members-change-send[disabled]", "Change members")

    # Casey attended: their hours go, so Mark absent asks first (#920).
    check(lv, [ctx.casey.id, ctx.cameron.id, ctx.drew.id], "absent")
    assert has_element?(lv, "#members-change-send", "Mark 2 absent")

    assert has_element?(
             lv,
             ~s|#members-change-send[data-confirm="Mark 2 members absent on Swiftwater training? Their hours go, and Mark attended gives back the activity's times, not their own."]|
           )

    assert has_element?(
             lv,
             ~s|#members-change-send[data-confirm-warning="Casey Dhillon's 2h 30m go."]|
           )

    # Only members with no reply: nothing is lost, so it doesn't ask.
    check(lv, [ctx.cameron.id, ctx.riley.id], "absent")
    assert has_element?(lv, "#members-change-send", "Mark 2 absent")
    refute has_element?(lv, "#members-change-send[data-confirm]")

    check(lv, [ctx.casey.id, ctx.cameron.id, ctx.drew.id], "attended")
    assert has_element?(lv, "#members-change-send", "Mark 2 attended")

    # Casey attended already: Mark attended greys out, and nothing is picked. Never Mark
    # absent, which would take Casey's hours.
    check(lv, [ctx.casey.id], "attended")
    assert has_element?(lv, "#members-change-choice[disabled]")
    assert has_element?(lv, "#members-change", "Everyone checked attended already.")
    refute has_element?(lv, "#members-change input[type=radio][checked]")
    assert has_element?(lv, "#members-change-send[disabled]", "Change members")
  end

  test "Mark absent changes them in place, and nothing stays checked (X)", ctx do
    AttendanceStub.stub(ctx.rows)
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    check(lv, [ctx.casey.id, ctx.cameron.id], "absent")

    lv
    |> form("#members-change-form", %{
      "member_ids" => [to_string(ctx.casey.id), to_string(ctx.cameron.id)],
      "change" => "absent"
    })
    |> render_submit()

    assert render(lv) =~ "2 members marked absent."
    assert has_element?(lv, "#member-row-#{ctx.casey.id} .marker-cant-make-it", "Absent")
    assert has_element?(lv, "#member-row-#{ctx.cameron.id} .marker-cant-make-it", "Absent")
    assert has_element?(lv, "#activity-panel-counts", "1 attended · 3 absent · 1 no reply")
    refute has_element?(lv, ~s|#members-change-form input[name="member_ids[]"][checked]|)
    assert [%ChangeSet{source: :change_attendance}] = Repo.all(ChangeSet)
  end

  test "Remove asks first, naming the hours that go (W)", ctx do
    AttendanceStub.stub(ctx.rows)
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    check(lv, [ctx.casey.id, ctx.cameron.id, ctx.riley.id], "remove")

    assert has_element?(
             lv,
             ~s|#members-change-send.btn-danger[data-confirm="Remove 3 members from Swiftwater training? They come off its attendance. Add members can put them back, as attended with the activity's times."]|,
             "Remove 3 members"
           )

    assert has_element?(
             lv,
             ~s|#members-change-send[data-confirm-warning="Casey Dhillon's 2h 30m go too."]|
           )

    lv
    |> form("#members-change-form", %{
      "member_ids" => [to_string(ctx.cameron.id)],
      "change" => "remove"
    })
    |> render_submit()

    assert render(lv) =~ "1 member removed."
    refute has_element?(lv, "#member-row-#{ctx.cameron.id}")
    refute Repo.get_by(Attendance, member_id: ctx.cameron.id)
  end

  test "a member whose attendance changed since is skipped, in a red toast", ctx do
    # D4H has Riley attending by now.
    changed =
      Enum.map(
        ctx.rows,
        &if(&1.member_id == ctx.riley.id, do: %{&1 | status: "attending"}, else: &1)
      )

    AttendanceStub.stub(changed)
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    lv
    |> form("#members-change-form", %{
      "member_ids" => [to_string(ctx.riley.id)],
      "change" => "absent"
    })
    |> render_submit()

    assert has_element?(lv, "#flash-error", "Riley Okafor was not changed")
  end

  test "once it's published, a hint, and Send an update is the only change (Z, #896 G)", ctx do
    ctx.activity |> Ecto.Changeset.change(is_published: true) |> Repo.update!()
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    assert has_element?(
             lv,
             "#members-locked",
             "Published, so attendance cannot be changed. Unpublish it with Change activity first."
           )

    assert has_element?(lv, "#members-change", "Send an update")
    refute has_element?(lv, "#members-change", "The activity's times")
    refute has_element?(lv, "#members-change", "Remove from the activity")
    refute has_element?(lv, "#members-add")

    check(lv, [ctx.alex.id, ctx.drew.id], "update")
    assert has_element?(lv, "#members-change-send", "Email 2 members")
  end

  test "a deleted activity offers no change", ctx do
    ctx.activity |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    refute has_element?(lv, "#members-change-form")
    refute has_element?(lv, "#activity-members input[type=checkbox]")
  end

  # After the start, Send an update emails the checked the same email, whatever their
  # attendance (#896): Alex and Casey attended, Drew was absent, Cameron and Riley never
  # replied.
  describe "Send an update after the start (#896)" do
    defp open_update(ctx, members) do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))

      lv
      |> form("#members-change-form", %{
        "member_ids" => Enum.map(members, &to_string(&1.id)),
        "change" => "update"
      })
      |> render_submit()

      assert_patch(lv, path(ctx) <> "/update")
      lv
    end

    test "lists who gets it in one table, and previews the one email", ctx do
      lv = open_update(ctx, [ctx.alex, ctx.drew, ctx.riley])

      assert has_element?(lv, "#update-who th", "Member")
      refute has_element?(lv, "#update-who th", "Attended")
      assert has_element?(lv, "#update-to-members #update-to-#{ctx.alex.id}", "Alex Chen")
      assert has_element?(lv, "#update-to-members #update-to-#{ctx.drew.id}", "Drew Patel")
      assert has_element?(lv, "#update-to-members #update-to-#{ctx.riley.id}", "Riley Okafor")
      refute has_element?(lv, "#update-to-attending")
      refute has_element?(lv, "#update-step", "Turned off reminders")

      refute has_element?(lv, "#update-preview-for")
      assert has_element?(lv, "#email-preview", "Open activity")
      refute has_element?(lv, "#email-preview", "You")
      refute has_element?(lv, "#email-preview", "I'll be there")

      assert has_element?(
               lv,
               ~s(#update-send[data-confirm="Email 3 members about Swiftwater training? Each gets your message and a link to the activity."])
             )
    end

    test "emails each the message and Open activity, and no reply buttons", ctx do
      lv = open_update(ctx, [ctx.alex, ctx.drew, ctx.riley])
      lv |> form("#update-form") |> render_submit(%{"message" => "Thanks for Tuesday."})

      assert_patch(lv, path(ctx))
      assert has_element?(lv, "#flash-info", "Sending 3 updates.")

      emails =
        for _ <- 1..3, into: %{} do
          assert_received {:email, %{to: [{name, _}]} = email}
          {name, email}
        end

      assert emails["Alex Chen"].subject == "Update: Swiftwater training"

      for {_name, email} <- emails do
        assert email.text_body =~ "Thanks for Tuesday."
        assert email.html_body =~ "Open activity"
        refute email.html_body =~ "You"
        refute email.html_body =~ "I'll be there"
        refute email.html_body =~ "Change your reply"
      end

      assert Repo.aggregate(ActivityUpdate, :count) == 3
    end
  end

  test "before the start, a table per reply, then the list (#895 A)", ctx do
    starts = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

    ctx.activity
    |> Ecto.Changeset.change(started_at: starts, finished_at: DateTime.add(starts, 2, :hour))
    |> Repo.update!()

    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    assert has_element?(lv, "#members-table #member-row-#{ctx.casey.id}")
    assert has_element?(lv, "#members-table #member-row-#{ctx.drew.id}")
    assert has_element?(lv, "#members-table #member-row-#{ctx.riley.id}")
    assert has_element?(lv, "#members-table-select-all")
    assert has_element?(lv, "#activity-members th", "Replied")

    assert has_element?(lv, "#members-change legend", "For the checked members")

    assert has_element?(
             lv,
             "#members-change",
             "Emails “Will you be there?” to the checked with no reply."
           )

    assert has_element?(
             lv,
             "#members-change",
             "The checked get your message and where they stand."
           )

    refute has_element?(lv, "#members-change", "Mark attended")

    assert has_element?(
             lv,
             "#members-change",
             "The checked come off the activity. Those who signed up get your message."
           )

    # Nothing picked at the start: the admin picks the change.
    refute has_element?(lv, "#members-change input[type=radio][checked]")
    assert has_element?(lv, "#members-change-send[disabled]", "Change members")
    assert has_element?(lv, "#members-bar-hint", "Check members, then select what to do.")
    refute has_element?(lv, "#members-remove")
  end

  test "Send attendance is gone with no scans (A4)", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    refute has_element?(lv, "#activity-send-attendance")
  end

  test "a member sees the tables, and their change sends nothing" do
    %{user: user, member: member, team: team} = member_with_login_fixture()
    activity = activity_fixture(team, %{started_at: ~U[2026-10-28 02:00:00Z]})
    attendance_fixture(activity, member)
    other = member_fixture(team)
    attendance_fixture(activity, other, %{status: "requested"})

    {:ok, lv, _html} =
      live(log_in_user(build_conn(), user), ~p"/teams/#{team}/activities/#{activity.id}/members")

    assert has_element?(lv, "#members-table #member-row-#{member.id}")
    refute has_element?(lv, "#members-change-form")

    render_hook(lv, "apply", %{"member_ids" => [to_string(other.id)], "change" => "absent"})
    assert Repo.all(ChangeSet) == []
  end

  describe "the Group filter (#895)" do
    setup ctx do
      leaders = group_fixture(ctx.team, %{title: "Team leaders"})
      group_member_fixture(leaders, ctx.casey)
      group_member_fixture(leaders, ctx.riley)
      %{leaders: leaders}
    end

    defp filter(lv, group),
      do: lv |> form("#members-filter", %{"form" => %{"group" => group}}) |> render_change()

    test "shows only the group's members, with the count, in the URL", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      assert has_element?(lv, "#members-tile-all", "5")
      refute has_element?(lv, "#members-filter-summary")

      filter(lv, ctx.leaders.id)
      assert_patch(lv, path(ctx) <> "?group=#{ctx.leaders.id}")
      assert has_element?(lv, "#members-filter-summary", "2 of 5 members, in Team leaders")
      assert has_element?(lv, "#members-table #member-row-#{ctx.casey.id}")
      assert has_element?(lv, "#members-table #member-row-#{ctx.riley.id}")
      refute has_element?(lv, "#member-row-#{ctx.alex.id}")
      refute has_element?(lv, "#member-row-#{ctx.drew.id}")
      assert has_element?(lv, "#members-tile-all", "2")
      assert has_element?(lv, "#members-tile-absent.is-zero", "0")
      assert has_element?(lv, "#activity-panel-counts", "2 attended · 1 absent · 2 no reply")

      {:ok, lv, _html} = live(ctx.conn, path(ctx) <> "?group=#{ctx.leaders.id}")
      refute has_element?(lv, "#member-row-#{ctx.alex.id}")
    end

    test "changing the filter unchecks the rows it hides", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      check(lv, [ctx.casey.id, ctx.cameron.id, ctx.riley.id], "absent")
      assert has_element?(lv, "#members-change-send", "Mark 3 absent")

      filter(lv, ctx.leaders.id)
      assert has_element?(lv, "#members-change-send", "Mark 2 absent")
      assert has_element?(lv, "#members-select-#{ctx.casey.id}[checked]")

      filter(lv, "")
      assert_patch(lv, path(ctx))
      assert has_element?(lv, "#members-change-send", "Mark 2 absent")
      refute has_element?(lv, "#members-select-#{ctx.cameron.id}[checked]")
    end

    test "a group nobody on the activity is in, or not the team's", ctx do
      empty = group_fixture(ctx.team, %{title: "Drivers"})
      {:ok, lv, _html} = live(ctx.conn, path(ctx) <> "?group=#{empty.id}")
      assert has_element?(lv, "#members-none-shown", "No members match")
      refute has_element?(lv, "#members-change-form")

      other = group_fixture(team_fixture(), %{title: "Elsewhere"})
      {:ok, lv, _html} = live(ctx.conn, path(ctx) <> "?group=#{other.id}")
      assert has_element?(lv, "#members-tile-all", "5")
      assert has_element?(lv, "#member-row-#{ctx.alex.id}")
    end

    test "before the start, it filters the reply table", ctx do
      starts = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

      ctx.activity
      |> Ecto.Changeset.change(started_at: starts, finished_at: DateTime.add(starts, 2, :hour))
      |> Repo.update!()

      {:ok, lv, _html} = live(ctx.conn, path(ctx) <> "?group=#{ctx.leaders.id}")
      assert has_element?(lv, "#members-table #member-row-#{ctx.riley.id}")
      refute has_element?(lv, "#member-row-#{ctx.cameron.id}")
    end

    test "a member filters too" do
      %{user: user, member: member, team: team} = member_with_login_fixture()
      activity = activity_fixture(team, %{started_at: ~U[2026-10-28 02:00:00Z]})
      attendance_fixture(activity, member)
      other = member_fixture(team)
      attendance_fixture(activity, other, %{status: "requested"})
      group = group_fixture(team, %{title: "Team leaders"})
      group_member_fixture(group, other)

      {:ok, lv, _html} =
        live(
          log_in_user(build_conn(), user),
          ~p"/teams/#{team}/activities/#{activity.id}/members"
        )

      filter(lv, group.id)
      refute has_element?(lv, "#member-row-#{member.id}")
      assert has_element?(lv, "#member-row-#{other.id}")
    end
  end

  # One table with a tile per reply and a name search (#920): Alex and Casey attended,
  # Drew is absent, and Cameron and Riley haven't replied.
  describe "the tiles and search (#920)" do
    defp search(lv, q),
      do: lv |> form("#members-filter", %{"form" => %{"q" => q}}) |> render_change()

    test "one table, the tiles from the start, and the bar under the list", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))

      assert has_element?(lv, ~s|#members-switch[aria-label="Attendance"]|)
      assert has_element?(lv, "#members-tile-all[aria-current]", "5")
      assert has_element?(lv, "#members-tile-attended", "2")
      assert has_element?(lv, "#members-tile-absent", "1")
      assert has_element?(lv, "#members-tile-no-reply", "2")

      for header <- ["Member", "Attendance", "Start", "Finish", "Hours"],
          do: assert(has_element?(lv, "#activity-members thead th", header))

      refute has_element?(lv, "#activity-members thead th", "Replied")
      assert has_element?(lv, "#member-row-#{ctx.casey.id}", "2h 30m")
      refute has_element?(lv, "#member-row-#{ctx.drew.id}", "1 hour")
      # Drew is absent, so the row has no hours, and the total leaves them out.
      assert has_element?(lv, "#members-hours", "3h 30m in total")

      assert has_element?(lv, "#members-bar #members-change-send[disabled]")
      assert has_element?(lv, "#members-bar-hint", "Check members, then select what to do.")
      check(lv, [ctx.casey.id], "absent")
      refute has_element?(lv, "#members-bar-hint")
    end

    test "a tile shows its rows, in the URL, and unchecks the rows it hides", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      check(lv, [ctx.casey.id, ctx.cameron.id, ctx.riley.id], "absent")
      assert has_element?(lv, "#members-change-send", "Mark 3 absent")

      lv |> element("#members-tile-no-reply") |> render_click()
      assert_patch(lv, path(ctx) <> "?status=no-reply")
      assert has_element?(lv, "#members-tile-no-reply[aria-current]")
      assert has_element?(lv, "#member-row-#{ctx.riley.id}")
      refute has_element?(lv, "#member-row-#{ctx.casey.id}")
      refute has_element?(lv, "#members-filter-summary")
      assert has_element?(lv, "#members-change-send", "Mark 2 absent")

      lv |> element("#members-tile-all") |> render_click()
      assert_patch(lv, path(ctx))
      refute has_element?(lv, "#members-select-#{ctx.casey.id}[checked]")
      assert has_element?(lv, "#members-select-#{ctx.cameron.id}[checked]")
    end

    test "search finds a name, keeps the tile, and unchecks the rows it hides", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx) <> "?status=no-reply")
      check(lv, [ctx.cameron.id, ctx.riley.id], "absent")

      search(lv, " oka ")
      assert_patch(lv, path(ctx) <> "?status=no-reply&q=oka")
      assert has_element?(lv, "#member-row-#{ctx.riley.id}")
      refute has_element?(lv, "#member-row-#{ctx.cameron.id}")
      # Counted against the tile: 1 of the 2 with no reply.
      assert has_element?(lv, "#members-filter-summary", "1 of 2 members")
      assert has_element?(lv, "#members-tile-no-reply", "2")
      assert has_element?(lv, "#members-change-send", "Mark 1 absent")

      search(lv, "nobody")
      assert has_element?(lv, "#members-none-shown", "No members match")
      assert has_element?(lv, "#members-none-shown", "Change the search or the filters.")
      refute has_element?(lv, "#members-search-all")
      refute has_element?(lv, "#members-change-form")

      # Casey attended: the empty state says where, and Search all members keeps the search.
      search(lv, "casey")
      assert has_element?(lv, "#members-none-shown", "Casey Dhillon is in Attended.")
      lv |> element("#members-search-all") |> render_click()
      assert_patch(lv, path(ctx) <> "?q=casey")
      assert has_element?(lv, "#member-row-#{ctx.casey.id}")
    end

    test "select all is in the header, over only the rows shown", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx) <> "?status=no-reply")
      assert has_element?(lv, "#members-table-select-all")
      boxes = lv |> element("#members-table") |> render()
      assert boxes =~ ~s(id="members-select-#{ctx.cameron.id}")
      assert boxes =~ ~s(id="members-select-#{ctx.riley.id}")
      refute boxes =~ ~s(id="members-select-#{ctx.casey.id}")
    end

    test "a status that doesn't fit the activity shows everyone", ctx do
      for status <- ["signed-up", "maybe"] do
        {:ok, lv, _html} = live(ctx.conn, path(ctx) <> "?status=#{status}")
        assert has_element?(lv, "#members-tile-all[aria-current]")
        assert has_element?(lv, "#member-row-#{ctx.alex.id}")
        assert has_element?(lv, "#member-row-#{ctx.riley.id}")
      end
    end

    test "a member sees the tiles, search, and table, with no boxes or bar" do
      %{user: user, member: member, team: team} = member_with_login_fixture()
      activity = activity_fixture(team, %{started_at: ~U[2026-10-28 02:00:00Z]})
      attendance_fixture(activity, member)
      other = member_fixture(team, %{name: "Riley Okafor"})
      attendance_fixture(activity, other, %{status: "requested"})
      tab = ~p"/teams/#{team}/activities/#{activity.id}/members"

      {:ok, lv, _html} = live(log_in_user(build_conn(), user), tab)
      assert has_element?(lv, "#members-tile-no-reply", "1")
      assert has_element?(lv, "#members-filter input[type=search]")
      refute has_element?(lv, "#members-table-select-all")
      refute has_element?(lv, "#members-bar")

      lv |> element("#members-tile-no-reply") |> render_click()
      assert has_element?(lv, "#member-row-#{other.id}")
      refute has_element?(lv, "#member-row-#{member.id}")

      search(lv, "riley")
      assert_patch(lv, tab <> "?status=no-reply&q=riley")
    end

    test "before the start: reply tiles, and Asked on any row that has one", ctx do
      starts = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

      ctx.activity
      |> Ecto.Changeset.change(started_at: starts, finished_at: DateTime.add(starts, 2, :hour))
      |> Repo.update!()

      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      assert has_element?(lv, ~s|#members-switch[aria-label="Replies"]|)
      assert has_element?(lv, "#members-tile-signed-up", "2")
      assert has_element?(lv, "#members-tile-cant-make-it", "1")
      assert has_element?(lv, "#members-tile-no-reply", "2")
      assert has_element?(lv, "#activity-members thead th", "Reply")
      refute has_element?(lv, "#activity-members thead th", "Asked")

      Repo.insert!(%Reminder{
        team_id: ctx.team.id,
        activity_id: ctx.activity.id,
        member_id: ctx.casey.id,
        sent_at: DateTime.add(DateTime.utc_now(), -1, :day),
        status: :sent
      })

      {:ok, lv, _html} = live(ctx.conn, path(ctx) <> "?status=signed-up")
      assert has_element?(lv, "#activity-members thead th", "Asked")
      assert has_element?(lv, "#member-asked-#{ctx.casey.id}", "Asked")
      assert has_element?(lv, "#member-row-#{ctx.casey.id} .marker-signed-up", "Signed up")
    end
  end

  test "elsewhere_text/2 names one match, and counts more" do
    row = fn name -> %Attendance{member: %App.Model.Member{name: name}} end

    by_status = [
      {"attending", [row.("Avery Chen"), row.("Blake Morrison"), row.("Casey Dhillon")]},
      {"absent", [row.("Drew Patel")]}
    ]

    assert Web.ActivityMembersLive.elsewhere_text(by_status, false) ==
             "3 match in Signed up. Drew Patel is in Can't make it."

    assert Web.ActivityMembersLive.elsewhere_text([{"absent", [row.("Drew Patel")]}], true) ==
             "Drew Patel is in Absent."
  end

  # The list by writing.md's Choices for checked rows (#920 I): one heading, the Actions
  # order, hints from the ticks, and a greyed choice that says why.
  describe "the list's words (#920)" do
    defp labels(lv) do
      lv
      |> element("#members-change-choice-choices")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("label")
      |> Enum.map(
        &(&1
          |> Floki.text()
          |> String.split("\n", trim: true)
          |> hd()
          |> String.trim())
      )
    end

    test "from the start: changes, then Send an update, then Remove", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))

      assert labels(lv) == [
               "Mark attended",
               "Mark absent",
               "Send an update",
               "Remove from the activity"
             ]

      check(lv, [ctx.alex.id, ctx.casey.id, ctx.drew.id], "absent")

      assert has_element?(
               lv,
               "#members-change",
               "The 2 attended lose their hours, 3h 30m. They stay on the activity. 1 is absent already."
             )

      assert has_element?(lv, "#members-change-send", "Mark 2 absent")
    end

    test "before the start: Ask for a reply, Send an update, then Remove", ctx do
      starts = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

      ctx.activity
      |> Ecto.Changeset.change(started_at: starts, finished_at: DateTime.add(starts, 2, :hour))
      |> Repo.update!()

      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      assert labels(lv) == ["Ask for a reply", "Send an update", "Remove from the activity"]

      check(lv, [ctx.casey.id, ctx.cameron.id, ctx.riley.id])

      assert has_element?(
               lv,
               "#members-change",
               "Emails “Will you be there?” to the 2 checked with no reply. 1 has replied."
             )

      # Checked, nothing picked: the button waits on a choice.
      assert has_element?(lv, "#members-change-send[disabled]", "Change members")
      assert has_element?(lv, "#members-bar-hint", "Select what to do.")

      check(lv, [ctx.casey.id, ctx.cameron.id, ctx.riley.id], "ask")
      assert has_element?(lv, "#members-change-send", "Ask 2 members")

      # Only replied checked: Ask greys out, and nothing is picked, never Send an update.
      check(lv, [ctx.alex.id, ctx.casey.id], "ask")
      assert has_element?(lv, "#members-change-choice[disabled]")
      assert has_element?(lv, "#members-change", "Everyone checked has replied.")
      refute has_element?(lv, "#members-change input[type=radio][checked]")
      assert has_element?(lv, "#members-change-send[disabled]", "Change members")
    end

    test "the step is /members/ask, and /members/remind is gone", ctx do
      assert ctx.conn |> get(path(ctx) <> "/remind") |> html_response(404)
    end
  end

  # Before the start, the list emails the checked members: Ask for a reply and Send an
  # update, each a step on its own route of this LiveView (#895 B, C). Casey signed up,
  # Drew can't make it, and Cameron, Riley, Dana, and Eli haven't replied: Dana turned
  # reminders off and Eli has no email. Cameron was reminded 2 days ago.
  describe "the steps before the start (#895)" do
    setup ctx do
      activity =
        activity_fixture(ctx.team, %{
          title: "Rope rescue training",
          started_at: DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)
        })

      dana =
        ctx.team
        |> member_fixture(%{name: "Dana Clark"})
        |> Ecto.Changeset.change(invitation_reminders: false)
        |> Repo.update!()

      eli = member_fixture(ctx.team, %{name: "Eli Haddad", email: nil})

      attendance_fixture(activity, ctx.casey, %{status: "attending"})
      attendance_fixture(activity, ctx.drew, %{status: "absent"})

      for m <- [ctx.cameron, ctx.riley, dana, eli],
          do: attendance_fixture(activity, m, %{status: "requested"})

      reminded_at = DateTime.add(DateTime.utc_now(), -2, :day)

      Repo.insert!(%Reminder{
        team_id: ctx.team.id,
        activity_id: activity.id,
        member_id: ctx.cameron.id,
        sent_at: reminded_at,
        status: :sent
      })

      %{
        activity: activity,
        dana: dana,
        eli: eli,
        everyone: [ctx.casey, ctx.drew, ctx.cameron, ctx.riley, dana, eli],
        reminded: Service.Format.month_day(reminded_at, ctx.team.timezone)
      }
    end

    defp open_step(lv, members, change) do
      lv
      |> form("#members-change-form", %{
        "member_ids" => Enum.map(members, &to_string(&1.id)),
        "change" => change
      })
      |> render_submit()
    end

    test "the button counts who each choice reaches (A)", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      refute has_element?(lv, "#activity-send-reminders")
      refute has_element?(lv, "#activity-send-update")

      check(lv, Enum.map(ctx.everyone, & &1.id), "ask")
      assert has_element?(lv, "#members-change-send", "Ask 2 members")

      check(lv, Enum.map(ctx.everyone, & &1.id), "update")
      assert has_element?(lv, "#members-change-send", "Email 5 members")

      # Casey signed up and Eli has no email: nobody to ask, so nothing is picked.
      check(lv, [ctx.casey.id, ctx.eli.id], "ask")
      assert has_element?(lv, "#members-change-choice[disabled]")
      assert has_element?(lv, "#members-change", "Nobody checked with no reply can get one.")
      assert has_element?(lv, "#members-change-send[disabled]", "Change members")
    end

    test "Ask for a reply names who gets it, and why the rest get none (B)", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      open_step(lv, ctx.everyone, "ask")
      assert_patch(lv, path(ctx) <> "/ask")

      assert has_element?(lv, "h1", "Ask for a reply")
      assert has_element?(lv, ".breadcrumbs", "Members")
      assert has_element?(lv, "#ask-to-#{ctx.cameron.id} td", ctx.reminded)
      assert has_element?(lv, "#ask-to-#{ctx.riley.id}")
      refute has_element?(lv, "#ask-to-#{ctx.riley.id} td", ctx.reminded)
      refute has_element?(lv, "#ask-step input[type=checkbox]")
      assert has_element?(lv, "#ask-send", "Send 2 emails")
      assert has_element?(lv, ~s(#ask-send[data-confirm^="Email 2 members about"]))

      assert has_element?(lv, "#left-out-replied", "1 signed up and 1 can't make it")
      assert has_element?(lv, "#left-out-reminders_off", "Dana Clark")
      assert has_element?(lv, "#left-out-no_email", "No email in D4H: Eli Haddad")

      assert has_element?(lv, "#email-preview", "Will you be there? Rope rescue training")
      assert has_element?(lv, "#email-preview", "I'll be there")
      refute render(lv) =~ "/replies/"
    end

    test "Ask for a reply emails only the checked, with the message (B)", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      open_step(lv, [ctx.riley, ctx.casey], "ask")
      refute has_element?(lv, "#ask-to-#{ctx.cameron.id}")
      assert has_element?(lv, "#left-out-replied", "1 signed up")

      lv |> form("#ask-form") |> render_change(%{"message" => "Bring your rope kit."})
      assert has_element?(lv, "#email-preview", "Bring your rope kit.")
      assert has_element?(lv, "#ask-send", "Send 1 email")

      lv |> form("#ask-form") |> render_submit(%{"message" => "Bring your rope kit."})
      assert_patch(lv, path(ctx))

      assert_received {:email, %{to: [{"Riley Okafor", _}], text_body: text}}
      assert text =~ "Bring your rope kit."
      refute_received {:email, _}
      assert has_element?(lv, "#flash-info", "Asking 1 member.")
      assert has_element?(lv, "#members-batch", "1 sent")
      refute has_element?(lv, ~s|#members-change-form input[name="member_ids[]"][checked]|)

      assert [%Reminder{status: :sent}] =
               Reminder |> where(member_id: ^ctx.riley.id) |> Repo.all()
    end

    test "the reminder's message starts with how many more are needed (#447)", ctx do
      ctx.activity |> Ecto.Changeset.change(enough_at: 5) |> Repo.update!()
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      open_step(lv, [ctx.riley], "ask")
      assert has_element?(lv, "#ask-message", "We need 4 more people.")
    end

    test "Back opens the tab with the filter and the ticks as they were", ctx do
      leaders = group_fixture(ctx.team, %{title: "Team leaders"})
      for m <- [ctx.casey, ctx.riley], do: group_member_fixture(leaders, m)

      {:ok, lv, _html} = live(ctx.conn, path(ctx) <> "?group=#{leaders.id}")
      open_step(lv, [ctx.casey, ctx.riley], "update")
      assert_patch(lv, path(ctx) <> "/update?group=#{leaders.id}")
      assert has_element?(lv, "#update-to-#{ctx.casey.id}")
      refute has_element?(lv, "#update-to-#{ctx.cameron.id}")

      lv |> element("#update-back") |> render_click()
      assert_patch(lv, path(ctx) <> "?group=#{leaders.id}")
      assert has_element?(lv, "#members-select-#{ctx.casey.id}[checked]")
      assert has_element?(lv, "#members-select-#{ctx.riley.id}[checked]")
      assert has_element?(lv, "#members-change-send", "Email 2 members")
    end

    test "a step opened with nothing checked goes to the tab", ctx do
      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(ctx.conn, path(ctx) <> "/ask")

      assert to == path(ctx)
      assert flash["error"] == "Select the members again."
    end

    test "Send an update lists the checked by reply, without tick boxes (C)", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      open_step(lv, ctx.everyone, "update")
      assert_patch(lv, path(ctx) <> "/update")

      assert has_element?(lv, "h1", "Send an update")
      assert has_element?(lv, "#update-to-attending", "Casey Dhillon")
      assert has_element?(lv, "#update-to-absent", "Drew Patel")
      assert has_element?(lv, "#update-to-requested", "Cameron Ruiz")
      refute has_element?(lv, "#update-step input[type=checkbox]")

      assert has_element?(
               lv,
               "#update-to-#{ctx.dana.id}",
               "Turned off reminders, so no reply buttons"
             )

      assert has_element?(lv, "#update-no-email", "Eli Haddad")
      assert has_element?(lv, "#update-send", "Send 5 emails")

      assert has_element?(
               lv,
               ~s(#update-send[data-confirm="Email 5 members about Rope rescue training? Each gets your message, whatever their reply."])
             )

      # A blank message skips the confirm and goes to the server, which refuses it.
      assert has_element?(lv, ~s(#update-send[data-confirm-needs="#update-message"]))

      assert has_element?(lv, "#email-preview", "Update: Rope rescue training")
      assert has_element?(lv, "#email-preview", "You're signed up.")

      lv
      |> form("#update-form")
      |> render_change(%{"message" => "Meet at the pullout.", "preview" => "ask"})

      assert has_element?(lv, "#email-preview", "Meet at the pullout.")
      assert has_element?(lv, "#email-preview", "I'll be there")

      lv
      |> form("#update-form")
      |> render_change(%{"message" => "Meet at the pullout.", "preview" => "open"})

      refute has_element?(lv, "#email-preview", "I'll be there")
    end

    test "Send an update with no message refuses, marks the box, and sends nothing", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      open_step(lv, [ctx.drew, ctx.riley], "update")

      lv |> form("#update-form") |> render_submit(%{"message" => " \n "})
      assert has_element?(lv, "#flash-error", "Enter a message.")
      assert has_element?(lv, "#update-step .field-error", "Enter a message.")
      refute_received {:email, _}
      assert Repo.all(ActivityUpdate) == []

      lv |> form("#update-form") |> render_change(%{"message" => "Meet at the pullout."})
      refute has_element?(lv, "#update-step .field-error")
    end

    test "Send an update emails the checked, then lists the send (C)", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      open_step(lv, [ctx.drew], "update")

      lv |> form("#update-form") |> render_submit(%{"message" => "Meet at the pullout."})
      assert_patch(lv, path(ctx))

      assert_received {:email,
                       %{to: [{"Drew Patel", _}], subject: "Update: Rope rescue training"}}

      refute_received {:email, _}
      assert has_element?(lv, "#flash-info", "Sending 1 update.")
      assert [%ActivityUpdate{status: :sent}] = Repo.all(ActivityUpdate)

      open_step(lv, [ctx.drew], "update")
      assert has_element?(lv, "#update-sent-before", "to 1 member")
      assert has_element?(lv, "#update-sent-before", "Meet at the pullout.")
    end

    test "a send after the start sends nothing, and the tab says why", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      open_step(lv, [ctx.riley], "ask")

      ctx.activity
      |> Ecto.Changeset.change(
        started_at: DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      lv |> form("#ask-form") |> render_submit(%{"message" => ""})
      assert_patch(lv, path(ctx))
      assert has_element?(lv, "#flash-error", "Reminders closed when the activity started.")
      refute_received {:email, _}
    end

    test "a member opening a step gets the tab", ctx do
      %{user: user, member: member, team: team} = member_with_login_fixture()
      activity = activity_fixture(team, %{started_at: ctx.activity.started_at})
      attendance_fixture(activity, member, %{status: "requested"})
      conn = log_in_user(build_conn(), user)
      tab = ~p"/teams/#{team}/activities/#{activity.id}/members"

      assert {:error, {:live_redirect, %{to: ^tab}}} = live(conn, tab <> "/update")

      {:ok, lv, _html} = live(conn, tab)
      refute has_element?(lv, "#members-change-form")
      assert has_element?(lv, "#members-table #member-row-#{member.id}")
    end
  end

  # Remove from the activity before the start (#895 D, E): the #704 page, as a step. Harper
  # hasn't replied, Riley can't make it, Drew signed up, and Sam signed up with no email.
  describe "Remove from the activity before the start (#704, #895)" do
    setup ctx do
      starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)

      activity =
        activity_fixture(ctx.team, %{
          title: "Save-On-Foods BBQ",
          started_at: starts,
          finished_at: DateTime.add(starts, 3, :hour)
        })

      add = fn name, status, attrs ->
        member = member_fixture(ctx.team, Map.put(attrs, :name, name))
        {member, attendance_fixture(activity, member, %{status: status})}
      end

      {harper, harper_row} = add.("Harper Nguyen", "requested", %{})
      {riley, riley_row} = add.("Riley Lam", "absent", %{})
      {drew, drew_row} = add.("Drew Park", "attending", %{})
      {sam, sam_row} = add.("Sam Rivera", "attending", %{email: nil})

      %{
        activity: activity,
        harper: harper,
        riley: riley,
        drew: drew,
        sam: sam,
        rows: [harper_row, riley_row, drew_row, sam_row]
      }
    end

    defp open_remove(ctx, members) do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))

      lv
      |> form("#members-change-form", %{
        "member_ids" => Enum.map(members, &to_string(&1.id)),
        "change" => "remove"
      })
      |> render_submit()

      assert_patch(lv, path(ctx) <> "/remove")
      lv
    end

    defp type(lv, params), do: lv |> form("#remove-form") |> render_change(params)

    test "the tab counts everyone checked, red, and asks nothing yet (D)", ctx do
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      check(lv, [ctx.harper.id, ctx.riley.id, ctx.drew.id], "remove")

      assert has_element?(lv, "#members-change-send.btn-danger", "Remove 3 members")
      refute has_element?(lv, "#members-change-send[data-confirm]")
    end

    test "who goes with no email, then who gets the message, previewed (E)", ctx do
      lv = open_remove(ctx, [ctx.harper, ctx.riley, ctx.drew])

      assert has_element?(lv, "h1", "Remove from the activity")
      assert has_element?(lv, ~s|table:has(#remove-no-email-table) th|, "Removed, no email")
      assert has_element?(lv, "#remove-no-email-table #remove-row-#{ctx.harper.id}", "No reply")

      assert has_element?(
               lv,
               "#remove-no-email-table #remove-row-#{ctx.riley.id}",
               "Can't make it"
             )

      assert has_element?(
               lv,
               ~s|table:has(#remove-emailed-table) th|,
               "Removed and emailed your message"
             )

      assert has_element?(lv, "#remove-emailed-table #remove-row-#{ctx.drew.id}", "Signed up")

      assert has_element?(
               lv,
               "#remove-signed-up-warning",
               "Each gets your message by email, because they signed up."
             )

      refute has_element?(lv, "#remove-intro", "D4H")
      refute has_element?(lv, "#remove-step input[name='member_ids[]']")

      assert has_element?(lv, "label[for=remove-message]", "Message to Drew Park")
      assert has_element?(lv, "#remove-preview-section", "What Drew Park gets")
      assert has_element?(lv, "#remove-preview-section", "You're no longer on Save-On-Foods BBQ")

      assert has_element?(
               lv,
               ~s|#remove-send[data-confirm="Remove 3 members from Save-On-Foods BBQ? Drew Park signed up, and gets your email. 2 others get no email: 1 no reply, 1 can't make it."]|,
               "Remove 3 members"
             )
    end

    # Nobody gets an email, so there's nothing for a step to ask: one confirm on the tab.
    test "with nobody signed up, the tab asks once and removes them, with no step", ctx do
      AttendanceStub.stub(ctx.rows)
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      check(lv, [ctx.harper.id, ctx.riley.id], "remove")

      assert has_element?(
               lv,
               ~s|#members-change-send[data-confirm="Remove 2 members from Save-On-Foods BBQ? Nobody gets an email. To undo, add them again."]|,
               "Remove 2 members"
             )

      lv
      |> form("#members-change-form", %{
        "member_ids" => [to_string(ctx.harper.id), to_string(ctx.riley.id)],
        "change" => "remove"
      })
      |> render_submit()

      refute has_element?(lv, "#remove-step")
      assert has_element?(lv, "#flash-info", "2 members removed.")
      refute has_element?(lv, "#member-row-#{ctx.harper.id}")
      refute has_element?(lv, "#member-row-#{ctx.riley.id}")
      refute_received {:email, _}

      assert Attendance
             |> where(activity_id: ^ctx.activity.id)
             |> Repo.all()
             |> Enum.map(& &1.member_id)
             |> Enum.sort() == Enum.sort([ctx.drew.id, ctx.sam.id])
    end

    # Nobody gets an email, so there's no message box and no confirm.
    test "a signed up member with no email needs no message", ctx do
      lv = open_remove(ctx, [ctx.sam])

      refute has_element?(lv, "#remove-message")
      refute has_element?(lv, "#remove-preview-section")
      refute has_element?(lv, "#remove-send[data-confirm]")

      assert has_element?(
               lv,
               "#remove-no-email",
               "Nobody gets an email. Sam Rivera has no email in D4H, so tell them yourself."
             )
    end

    # The exception, worded as accepting your own chores is (#697). A required why would
    # collect filler, so it's optional.
    test "Remove without emailing them sends no email, and the why is optional", ctx do
      AttendanceStub.stub(ctx.rows)
      lv = open_remove(ctx, [ctx.drew])
      refute has_element?(lv, "#remove-skip-email[checked]")

      type(lv, %{"skip_email" => "true"})

      assert has_element?(lv, "label[for=remove-message]", "Why you removed Drew Park (optional)")
      assert has_element?(lv, "#remove-no-email-table #remove-row-#{ctx.drew.id}")
      refute has_element?(lv, "#remove-preview-section")
      refute has_element?(lv, "#remove-send[data-confirm]")

      lv |> form("#remove-form") |> render_submit(%{"skip_email" => "true"})

      assert_patch(lv, path(ctx))
      assert has_element?(lv, "#flash-info", "1 member removed.")
      refute_received {:email, _}
    end

    test "removing writes D4H and the copy, says who gets the email, and clears the ticks",
         ctx do
      AttendanceStub.stub(ctx.rows)
      lv = open_remove(ctx, [ctx.harper, ctx.drew, ctx.sam])
      type(lv, %{"message" => "Sorry, it's full."})

      lv |> form("#remove-form") |> render_submit(%{"message" => "Sorry, it's full."})

      assert_patch(lv, path(ctx))
      assert has_element?(lv, "#flash-info", "3 members removed. Drew Park gets your email.")
      refute has_element?(lv, "#member-row-#{ctx.drew.id}")
      refute has_element?(lv, ~s|#members-change-form input[name="member_ids[]"][checked]|)

      assert Attendance
             |> where(activity_id: ^ctx.activity.id)
             |> Repo.all()
             |> Enum.map(& &1.member_id) ==
               [ctx.riley.id]

      assert %ChangeSet{source: :remove} = Repo.get_by!(ChangeSet, activity_id: ctx.activity.id)
      assert_received {:email, %{to: [{"Drew Park", _}]}}
    end

    test "no message for a member who gets an email refuses, marks the box, and removes nobody",
         ctx do
      lv = open_remove(ctx, [ctx.drew])

      lv |> form("#remove-form") |> render_submit(%{"message" => " "})

      assert has_element?(lv, "#flash-error", "Enter a message for the signed up members.")
      assert has_element?(lv, ".field-error", "Enter a message for the signed up members.")
      assert has_element?(lv, "#remove-step")
      assert Repo.get_by(Attendance, member_id: ctx.drew.id)

      type(lv, %{"message" => "Sorry, it's full."})
      refute has_element?(lv, ".field-error")
    end

    test "Back opens the tab with the ticks as they were", ctx do
      lv = open_remove(ctx, [ctx.harper, ctx.drew])

      lv |> element("#remove-back") |> render_click()
      assert_patch(lv, path(ctx))
      assert has_element?(lv, "#members-select-#{ctx.harper.id}[checked]")
      assert has_element?(lv, "#members-select-#{ctx.drew.id}[checked]")
      assert has_element?(lv, "#members-change-send", "Remove 2 members")
    end

    # The stale check: published since the step opened, so RemoveMembers refuses.
    test "published since the step opened removes nobody, and the tab says why", ctx do
      lv = open_remove(ctx, [ctx.drew])
      ctx.activity |> Ecto.Changeset.change(is_published: true) |> Repo.update!()

      lv |> form("#remove-form") |> render_submit(%{})

      assert_patch(lv, path(ctx))
      assert has_element?(lv, "#flash-error", "Nobody was removed.")
      assert Repo.get_by(Attendance, member_id: ctx.drew.id)
    end

    test "a published activity offers no Remove", ctx do
      ctx.activity |> Ecto.Changeset.change(is_published: true) |> Repo.update!()
      {:ok, lv, _html} = live(ctx.conn, path(ctx))
      refute has_element?(lv, "#members-change", "Remove from the activity")

      assert {:error, {:live_redirect, %{flash: flash}}} = live(ctx.conn, path(ctx) <> "/remove")
      assert flash["error"] == "Select the members again."
    end
  end
end
