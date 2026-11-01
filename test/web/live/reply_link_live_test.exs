defmodule Web.ReplyLinkLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AttendanceStub
  alias App.Model.ChangeSet
  alias App.Repo
  alias Web.ReplyLinks

  # A reminder's link, with no login (#444): a form with the email's answer selected,
  # sent by a plain post (#488).
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

  test "opening the link selects the email's answer and changes nothing; Send reply sends it",
       %{conn: conn, member: member, activity: activity, row: row} do
    AttendanceStub.stub([row])
    path = ReplyLinks.reply_path(member, activity, :yes)
    {:ok, lv, _html} = live(conn, path)

    assert has_element?(lv, "h1", "Training night")
    assert has_element?(lv, ".hint", "Coast Range SAR")
    assert has_element?(lv, "#reply-link-form legend", "Will you be there?")
    assert has_element?(lv, "#reply-link-yes[checked]")
    refute has_element?(lv, "#reply-link-no[checked]")
    refute has_element?(lv, "#reply-link-was")
    assert has_element?(lv, "#reply-link-open", "Open activity")
    refute_received {:d4h_write, _id, _body}
    assert Repo.all(ChangeSet) == []

    [reply_path, "reply=yes"] = String.split(path, "?")
    conn = post(conn, reply_path, %{"reply" => "yes"})

    assert redirected_to(conn) == reply_path
    assert_received {:d4h_write, _id, %{"status" => "ATTENDING"}}

    {:ok, lv, _html} = live(build_conn(), reply_path)
    refute has_element?(lv, "#reply-link-form")
    assert has_element?(lv, "#reply-link-state", "Signed up")
    assert has_element?(lv, ~s(#reply-link-change[href="#{reply_path}?change=1"]), "Change")

    assert has_element?(
             lv,
             ~s(#reply-link-calendar[href="#{reply_path}/calendar"]),
             "Add to calendar"
           )

    # Nobody is logged in: the member's own set, sent by no user.
    assert [%ChangeSet{source: :member, applied_by_user_id: nil, proposed_by_user_id: nil}] =
             Repo.all(ChangeSet)
  end

  test "Can't make it in the email selects Can't make it",
       %{conn: conn, member: member, activity: activity} do
    {:ok, lv, _html} = live(conn, ReplyLinks.reply_path(member, activity, :no))

    assert has_element?(lv, "#reply-link-no[checked]")
    refute has_element?(lv, "#reply-link-yes[checked]")
  end

  test "a link with no answer selects nothing, and sending nothing asks for one",
       %{conn: conn, member: member, activity: activity} do
    path = ReplyLinks.reply_path(member, activity)
    {:ok, lv, _html} = live(conn, path)

    refute has_element?(lv, "#reply-link-form input[checked]")

    conn = post(conn, path, %{})
    assert redirected_to(conn) == path

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Select I'll be there or Can't make it."

    refute_received {:d4h_write, _id, _body}
  end

  # However they came off, a team admin's Remove members (#704) or D4H.
  test "a member no longer on the activity is told so",
       %{conn: conn, member: member, activity: activity, row: row} do
    Repo.delete!(row)
    {:ok, lv, _html} = live(conn, ReplyLinks.reply_path(member, activity, :yes))

    refute has_element?(lv, "#reply-link-form")
    assert has_element?(lv, "#reply-link-gone", "You're no longer on this activity.")
  end

  test "the same answer as their reply shows the reply, not the form",
       %{conn: conn, member: member, activity: activity, row: row} do
    row |> Ecto.Changeset.change(status: "attending") |> Repo.update!()
    {:ok, lv, _html} = live(conn, ReplyLinks.reply_path(member, activity, :yes))

    refute has_element?(lv, "#reply-link-form")
    assert has_element?(lv, "#reply-link-state", "Signed up")
  end

  test "the other answer shows their reply over the form",
       %{conn: conn, member: member, activity: activity, row: row} do
    row |> Ecto.Changeset.change(status: "absent") |> Repo.update!()
    {:ok, lv, _html} = live(conn, ReplyLinks.reply_path(member, activity, :yes))

    assert has_element?(lv, "#reply-link-was", "Your reply: Can't make it")
    assert has_element?(lv, "#reply-link-yes[checked]")
  end

  test "Change opens the form with their reply selected",
       %{conn: conn, member: member, activity: activity, row: row} do
    row |> Ecto.Changeset.change(status: "absent") |> Repo.update!()
    path = ReplyLinks.reply_path(member, activity)
    {:ok, lv, _html} = live(conn, path <> "?change=1")

    assert has_element?(lv, "#reply-link-no[checked]")
    refute has_element?(lv, "#reply-link-was")
  end

  test "replies close at the start", %{conn: conn, team: team, member: member} do
    started = DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
    activity = activity_fixture(team, %{started_at: started})
    attendance_fixture(activity, member, %{status: "requested"})
    path = ReplyLinks.reply_path(member, activity)

    {:ok, lv, _html} = live(conn, path <> "?reply=yes")

    assert has_element?(lv, "#reply-link-closed", "Replies closed when it started.")
    refute has_element?(lv, "#reply-link-form")
    assert has_element?(lv, "#reply-link-open")

    # A form left open from before the start.
    conn = post(conn, path, %{"reply" => "yes"})
    assert redirected_to(conn) == path <> "?reply=yes"
    assert Phoenix.Flash.get(conn.assigns.flash, :error)
    refute_received {:d4h_write, _id, _body}
  end

  test "Add to calendar is the link's activity as an .ics file, with no login",
       %{conn: conn, member: member, activity: activity} do
    conn = get(conn, ReplyLinks.reply_path(member, activity) <> "/calendar")

    assert response(conn, 200) =~ "SUMMARY:Training night"
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "text/calendar"
  end

  test "Add to calendar from a bad link, or for a deleted activity, is not found",
       %{conn: conn, team: team, member: member} do
    deleted =
      activity_fixture(team, %{deleted_at: DateTime.truncate(DateTime.utc_now(), :second)})

    for path <- ["/replies/made-up", ReplyLinks.reply_path(member, deleted)] do
      assert_error_sent 404, fn -> get(conn, path <> "/calendar") end
    end
  end

  test "a bad link, or one naming another team's activity, does nothing",
       %{conn: conn, member: member} do
    other_activity = activity_fixture(team_fixture())

    for path <- ["/replies/made-up", ReplyLinks.reply_path(member, other_activity)] do
      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "h1", "This link does not work")

      conn = post(conn, path, %{"reply" => "yes"})
      assert redirected_to(conn) == path
    end

    refute_received {:d4h_write, _id, _body}
  end

  describe "logged in" do
    # A team admin of 2 teams, who last opened the other one.
    setup %{conn: conn, team: team} do
      other = team_fixture(%{name: "Alpine SAR"})
      manager_fixture(team, %{email: "alex@example.com"})
      manager_fixture(other, %{email: "alex@example.com"})
      user = App.AccountsFixtures.user_fixture(%{email: "alex@example.com"})
      user = user |> Ecto.Changeset.change(last_team_id: other.id) |> Repo.update!()
      %{conn: log_in_user(conn, user)}
    end

    test "the bar names the link's team, and Open activity needs no login",
         %{conn: conn, member: member, activity: activity} do
      {:ok, lv, _html} = live(conn, ReplyLinks.reply_path(member, activity, :yes))

      assert has_element?(lv, "#nav-area", "Coast Range SAR")
      assert has_element?(lv, "#reply-link-open", "Open activity")
      refute has_element?(lv, "#reply-link-open + .hint")
    end

    test "on a team they don't open, the bar stays theirs and there is no Open activity",
         %{conn: conn} do
      team = team_fixture(%{name: "Pemberton SAR"})
      member = member_fixture(team)
      activity = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), 1, :day)})
      {:ok, lv, _html} = live(conn, ReplyLinks.reply_path(member, activity))

      assert has_element?(lv, "#nav-area", "Alpine SAR")
      refute has_element?(lv, "#reply-link-open")
    end

    test "a bad link opens activities, not Log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/replies/made-up")

      assert has_element?(lv, "#reply-link-activities", "Open activities")
      refute has_element?(lv, "#reply-link-login")
    end
  end
end
