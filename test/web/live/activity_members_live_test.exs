defmodule Web.ActivityMembersLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AttendanceStub
  alias App.Model.Attendance
  alias App.Model.ChangeSet
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

    assert has_element?(lv, "#members-attended #member-row-#{ctx.alex.id}")
    assert has_element?(lv, "#members-absent #member-row-#{ctx.drew.id}")
    assert has_element?(lv, "#members-no-reply #member-row-#{ctx.riley.id}")
    assert has_element?(lv, "#members-attended-select-all")
    assert has_element?(lv, ~s|label[for="members-select-#{ctx.casey.id}"]|, "Casey Dhillon")

    assert has_element?(lv, "#members-change legend", "Change the checked members")
    assert has_element?(lv, "#members-change", "The activity's times, 19:00 to 21:30.")
    assert has_element?(lv, "#members-change", "They stay on the activity, with no hours.")
    assert has_element?(lv, "#members-change", "Add members puts them back, as attended.")
    assert has_element?(lv, "#members-change-send[disabled]", "Change members")
    assert has_element?(lv, "#members-add", "Add members")
    refute has_element?(lv, "#members-remove")
  end

  test "the button counts the members its change changes (V)", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    check(lv, [ctx.casey.id, ctx.cameron.id])
    assert has_element?(lv, "#members-change-send[disabled]", "Change members")

    check(lv, [ctx.casey.id, ctx.cameron.id, ctx.drew.id], "absent")
    assert has_element?(lv, "#members-change-send", "Mark 2 absent")
    refute has_element?(lv, "#members-change-send[data-confirm]")

    check(lv, [ctx.casey.id, ctx.cameron.id, ctx.drew.id], "attended")
    assert has_element?(lv, "#members-change-send", "Mark 2 attended")

    check(lv, [ctx.casey.id], "attended")
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
    assert has_element?(lv, "#members-absent #member-row-#{ctx.casey.id}")
    assert has_element?(lv, "#members-absent #member-row-#{ctx.cameron.id}")
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

  test "once it's published, a hint and no checkboxes (Z)", ctx do
    ctx.activity |> Ecto.Changeset.change(is_published: true) |> Repo.update!()
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    assert has_element?(
             lv,
             "#members-locked",
             "Published, so attendance cannot be changed. Unpublish it with Change activity first."
           )

    refute has_element?(lv, "#members-change-form")
    refute has_element?(lv, "#activity-members input[type=checkbox]")
    assert has_element?(lv, ~s|#member-row-#{ctx.alex.id} a[href^="/teams/"]|, "Alex Chen")
    refute has_element?(lv, "#members-add")
  end

  test "before the start, one table and no checkboxes, as today", ctx do
    starts = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

    ctx.activity
    |> Ecto.Changeset.change(started_at: starts, finished_at: DateTime.add(starts, 2, :hour))
    |> Repo.update!()

    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    assert has_element?(lv, "#members-table #member-row-#{ctx.riley.id}", "No reply")
    refute has_element?(lv, "#members-change-form")
    assert has_element?(lv, "#members-remove", "Remove members")
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

    assert has_element?(lv, "#members-attended #member-row-#{member.id}")
    refute has_element?(lv, "#members-change-form")

    render_hook(lv, "apply", %{"member_ids" => [to_string(other.id)], "change" => "absent"})
    assert Repo.all(ChangeSet) == []
  end
end
