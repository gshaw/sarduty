defmodule Web.ActivityRemoveMembersLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AttendanceStub
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Repo

  # A team admin takes members off a coming activity (#704), with D4H stubbed.
  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)

    activity =
      activity_fixture(team, %{
        title: "Save-On-Foods BBQ",
        started_at: starts,
        finished_at: DateTime.add(starts, 3, :hour)
      })

    add = fn name, status, attrs ->
      member = member_fixture(team, Map.put(attrs, :name, name))
      {member, attendance_fixture(activity, member, %{status: status})}
    end

    {harper, harper_row} = add.("Harper Nguyen", "requested", %{})
    {riley, riley_row} = add.("Riley Okafor", "absent", %{})
    {drew, drew_row} = add.("Drew Patel", "attending", %{})
    {sam, sam_row} = add.("Sam Rivera", "attending", %{email: nil})

    %{
      conn: log_in_user(conn, user),
      team: team,
      activity: activity,
      harper: harper,
      riley: riley,
      drew: drew,
      sam: sam,
      rows: [harper_row, riley_row, drew_row, sam_row]
    }
  end

  defp path(ctx), do: ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/members/remove"

  # The message box shows once a checked member gets an email.
  defp check(lv, members, message \\ nil) do
    params = %{"member_ids" => Enum.map(members, &to_string(&1.id))}
    lv |> form("#remove-form", params) |> render_change()

    if message do
      params = Map.put(params, "message", message)
      lv |> form("#remove-form", params) |> render_change()
      params
    else
      params
    end
  end

  test "the activity's Members tab links here", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
    assert has_element?(lv, ~s|#members-remove[href="#{path(ctx)}"]|, "Remove members")
  end

  test "a table per reply, nothing checked, and the no email hint", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    assert has_element?(lv, "#remove-requested", "Harper Nguyen")
    assert has_element?(lv, "#remove-absent", "Riley Okafor")
    assert has_element?(lv, "#remove-attending", "Drew Patel")
    assert has_element?(lv, "#remove-signed-up-warning")
    assert has_element?(lv, "#remove-row-#{ctx.sam.id}", "No email in D4H, so tell them yourself")
    refute has_element?(lv, "#remove-row-#{ctx.drew.id}", "No email")
    refute has_element?(lv, ~s|#remove-form input[name="member_ids[]"][checked]|)
    assert has_element?(lv, "#remove-send[disabled]", "Remove members")
    refute has_element?(lv, "#remove-message")
  end

  test "a signed up member with an email needs a message, previewed, and a confirm", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    check(lv, [ctx.harper, ctx.riley, ctx.drew])

    assert has_element?(lv, "label[for=remove-message]", "Message to Drew Patel")
    assert has_element?(lv, "#remove-preview-section", "What Drew Patel gets")
    assert has_element?(lv, "#remove-preview-section", "You're no longer on Save-On-Foods BBQ")

    assert has_element?(
             lv,
             ~s|#remove-send[data-confirm="Remove 3 members from Save-On-Foods BBQ? Drew Patel signed up, and gets your email. 2 others get no email: 1 no reply, 1 can't make it."]|,
             "Remove 3 members"
           )
  end

  # Option 2: nobody gets an email, so there's no message box and no confirm.
  test "a signed up member with no email needs no message", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    check(lv, [ctx.sam])

    refute has_element?(lv, "#remove-message")
    refute has_element?(lv, "#remove-preview-section")
    refute has_element?(lv, "#remove-send[data-confirm]")

    assert has_element?(
             lv,
             "#remove-no-email",
             "Nobody gets an email. Sam Rivera has no email in D4H, so tell them yourself."
           )
  end

  test "removing writes D4H and the copy, and says who gets the email", ctx do
    AttendanceStub.stub(ctx.rows)
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    params = check(lv, [ctx.harper, ctx.drew, ctx.sam], "Sorry, it's full.")

    lv |> form("#remove-form", params) |> render_submit()

    {to, flash} = assert_redirect(lv)
    assert to == ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}"
    assert flash["info"] == "3 members removed. Drew Patel gets your email."

    assert Attendance |> Repo.all() |> Enum.map(& &1.member_id) == [ctx.riley.id]
    assert %ChangeSet{source: :remove} = Repo.get_by!(ChangeSet, activity_id: ctx.activity.id)
    assert_received {:email, %{to: [{"Drew Patel", _}]}}
  end

  test "no message for a member who gets an email refuses, and removes nobody", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    params = check(lv, [ctx.drew], " ")

    lv |> form("#remove-form", params) |> render_submit()

    assert render(lv) =~ "Enter a message for the signed up members."
    assert length(Repo.all(Attendance)) == 4
  end

  test "a published activity sends the visitor back", ctx do
    ctx.activity |> Ecto.Changeset.change(is_published: true) |> Repo.update!()

    assert {:error, {:live_redirect, %{flash: flash}}} = live(ctx.conn, path(ctx))

    assert flash["error"] ==
             "Published, so nobody can be removed. Unpublish it with Change activity first."
  end

  # Team pages are for team admins.
  test "a member gets nothing" do
    %{user: user, team: team} = member_with_login_fixture()
    activity = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), 3, :day)})
    conn = log_in_user(build_conn(), user)

    assert_error_sent 404, fn ->
      get(conn, ~p"/teams/#{team}/activities/#{activity.id}/members/remove")
    end
  end
end
