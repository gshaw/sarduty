defmodule Web.ReplyLinkLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AttendanceStub
  alias App.Model.ChangeSet
  alias App.Repo
  alias Web.ReplyLinks

  # A reminder's link, with no login (#444).
  setup do
    team = team_fixture(%{d4h_access_key: "team-key", name: "Coast Range SAR"})
    member = member_fixture(team, %{name: "Cameron Ruiz"})
    starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)

    activity =
      activity_fixture(team, %{
        title: "Training night",
        started_at: starts,
        finished_at: DateTime.add(starts, 3, :hour)
      })

    row = attendance_fixture(activity, member, %{status: "requested"})
    %{team: team, member: member, activity: activity, row: row}
  end

  test "opening the link changes nothing; the member selects a button",
       %{conn: conn, member: member, activity: activity, row: row} do
    AttendanceStub.stub([row])
    {:ok, lv, _html} = live(conn, ReplyLinks.reply_path(member, activity))

    assert has_element?(lv, "h1", "Training night")
    assert has_element?(lv, ".hint", "Coast Range SAR")
    assert has_element?(lv, "#reply-link-open", "Open activity")
    refute_received {:d4h_write, _id, _body}
    assert Repo.all(ChangeSet) == []

    lv |> element("#reply-link-yes") |> render_click()

    assert_received {:d4h_write, _id, %{"status" => "ATTENDING"}}
    assert has_element?(lv, "#reply-link-state", "Signed up")
    assert has_element?(lv, "#reply-link-change", "Change")

    # Nobody is logged in: the member's own set, sent by no user.
    assert [%ChangeSet{source: :member, applied_by_user_id: nil, proposed_by_user_id: nil}] =
             Repo.all(ChangeSet)
  end

  test "replies close at the start", %{conn: conn, team: team, member: member} do
    started = DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
    activity = activity_fixture(team, %{started_at: started})
    attendance_fixture(activity, member, %{status: "requested"})

    {:ok, lv, _html} = live(conn, ReplyLinks.reply_path(member, activity))

    assert has_element?(lv, "#reply-link-closed", "Replies closed when it started.")
    refute has_element?(lv, "#reply-link-yes")
    assert has_element?(lv, "#reply-link-open")
  end

  test "a bad link, or one naming another team's activity, does nothing",
       %{conn: conn, member: member} do
    other_activity = activity_fixture(team_fixture())

    for path <- ["/replies/made-up", ReplyLinks.reply_path(member, other_activity)] do
      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "h1", "This link does not work")
    end
  end
end
