defmodule Web.ActivityAddMembersLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AttendanceStub
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Repo

  # A team admin adds members to a coming activity (#564), with D4H stubbed.
  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)

    activity =
      activity_fixture(team, %{
        title: "Boat handling night",
        started_at: starts,
        finished_at: DateTime.add(starts, 3, :hour)
      })

    boats = group_fixture(team, %{title: "Boat Operators"})
    eli = member_fixture(team, %{name: "Eli Haddad"})
    wren = member_fixture(team, %{name: "Wren Adams"})
    dana = member_fixture(team, %{name: "Dana Clark"})
    jo = member_fixture(team, %{name: "Jo Park"})
    gerry = member_fixture(team, %{name: "Gerry Test"})
    for m <- [eli, wren, dana, jo], do: group_member_fixture(boats, m)
    attendance_fixture(activity, dana, %{status: "requested"})
    day = Date.add(Date.utc_today(), 3)
    away_period_fixture(jo, Date.add(day, -2), Date.add(day, 2))

    %{
      conn: log_in_user(conn, user),
      team: team,
      activity: activity,
      boats: boats,
      eli: eli,
      wren: wren,
      dana: dana,
      jo: jo,
      gerry: gerry
    }
  end

  defp path(ctx), do: ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/members/add"

  test "by group and by name, naming who the group left out", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    assert has_element?(lv, "#members-nothing-to-add")

    lv |> form("#add-group-form", %{"group-id" => ctx.boats.id}) |> render_submit()
    lv |> form("#add-member-form", %{"member-id" => ctx.gerry.id}) |> render_submit()

    assert has_element?(lv, "#to-add-#{ctx.eli.id}", "In the Boat Operators group")
    assert has_element?(lv, "#to-add-#{ctx.gerry.id}", "Added by name")

    assert has_element?(
             lv,
             "#left-out-on-activity",
             "On the activity already, so left out: Dana Clark."
           )

    assert has_element?(lv, "#left-out-away", "so left out: Jo Park. Add them by name")
    refute has_element?(lv, "#to-add-#{ctx.jo.id}")
    assert has_element?(lv, "#members-send", "Add 3 members")

    lv |> element("#remove-#{ctx.wren.id}") |> render_click()
    refute has_element?(lv, "#to-add-#{ctx.wren.id}")
    assert has_element?(lv, "#members-send", "Add 2 members")

    # By name, someone away goes after all.
    lv |> form("#add-member-form", %{"member-id" => ctx.jo.id}) |> render_submit()
    assert has_element?(lv, "#to-add-#{ctx.jo.id}", "Added by name")
    refute has_element?(lv, "#left-out-away")
  end

  test "adding writes D4H and the copy, and says nobody was emailed", ctx do
    AttendanceStub.stub([])
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    lv |> form("#add-group-form", %{"group-id" => ctx.boats.id}) |> render_submit()
    lv |> form("#add-member-form", %{"member-id" => ctx.gerry.id}) |> render_submit()

    lv |> form("#members-add-form") |> render_submit()

    {path, flash} = assert_redirect(lv)
    assert path == ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}"
    assert flash["info"] == "3 members added. Nobody was emailed."

    for _ <- 1..3, do: assert_received({:d4h_write, :create, %{"status" => "REQUESTED"}})
    refute_received {:d4h_write, _, _}

    added = for a <- Repo.all(Attendance), a.status == "requested", do: a.member_id
    assert Enum.sort(added) == Enum.sort([ctx.eli.id, ctx.wren.id, ctx.gerry.id, ctx.dana.id])
    assert %ChangeSet{source: :invite} = Repo.get_by!(ChangeSet, activity_id: ctx.activity.id)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
    assert has_element?(lv, "#member-row-#{ctx.eli.id}", "No reply")
    assert has_element?(lv, "#activity-send-reminders", "Send reminders")
  end

  test "a published activity sends the visitor back", ctx do
    ctx.activity |> Ecto.Changeset.change(is_published: true) |> Repo.update!()

    assert {:error, {:live_redirect, %{to: to, flash: flash}}} = live(ctx.conn, path(ctx))
    assert to == ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}"

    assert flash["error"] ==
             "Published, so nobody can be added. Unpublish it with Change activity first."
  end

  test "a started activity sends the visitor back", ctx do
    started = DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
    ctx.activity |> Ecto.Changeset.change(started_at: started) |> Repo.update!()

    assert {:error, {:live_redirect, %{flash: flash}}} = live(ctx.conn, path(ctx))
    assert flash["error"] == "The activity has started, so nobody can be added."
  end

  # Team pages are for team admins, so a member sends it no event either.
  test "a member gets nothing" do
    %{user: user, team: team} = member_with_login_fixture()
    activity = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), 3, :day)})
    conn = log_in_user(build_conn(), user)

    assert_error_sent 404, fn ->
      get(conn, ~p"/teams/#{team}/activities/#{activity.id}/members/add")
    end
  end
end
