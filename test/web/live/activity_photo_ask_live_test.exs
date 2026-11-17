defmodule Web.ActivityPhotoAskLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ActivityPhotoAsk
  alias App.Operation.SetPhotoAsks
  alias App.Repo
  alias Service.Format

  # cspell:ignore Noor -- Noor Aziz, of the Coast Range SAR cast
  # Ask for photos (#1034): a team admin emails everyone who attended an activity a link
  # to add their photos.
  setup %{conn: conn} do
    team = member_logins_team_fixture(%{name: "Coast Range SAR", photos_enabled: true})
    admin = user_fixture()
    manager_fixture(team, %{email: admin.email, name: "Alex Chen"})
    started_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

    activity =
      activity_fixture(team, %{
        title: "Swiftwater training",
        started_at: started_at,
        finished_at: DateTime.add(started_at, 2, :hour)
      })

    attended = fn name, attrs ->
      member = member_fixture(team, Map.merge(%{name: name, d4h_permission: 2}, attrs))
      attendance_fixture(activity, member)
      member
    end

    cam = attended.("Cameron Ruiz", %{})
    noor = attended.("Noor Aziz", %{})
    jordan = attended.("Jordan Lee", %{email: nil})
    riley = attended.("Riley Okafor", %{})
    SetPhotoAsks.call(riley, false)
    eli = attended.("Eli Haddad", %{})
    activity_photo_fixture(activity, %{member_id: eli.id})
    # On the list, and did not come.
    absent = member_fixture(team, %{name: "Sam Rivera"})
    attendance_fixture(activity, absent, %{status: "absent"})

    %{
      conn: log_in_user(conn, admin),
      team: team,
      activity: activity,
      cam: cam,
      noor: noor,
      jordan: jordan,
      absent: absent
    }
  end

  defp ask_path(team, activity), do: ~p"/teams/#{team}/activities/#{activity.id}/photos/ask"
  defp tab(team, activity), do: ~p"/teams/#{team}/activities/#{activity.id}/photos"

  test "lists who gets an email, and why the rest who attended do not", ctx do
    {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, ctx.activity))

    assert page_title(lv) =~ "Swiftwater training · Ask for photos"
    assert has_element?(lv, "h1", "Ask for photos")
    assert has_element?(lv, ~s|.breadcrumbs a[href="#{tab(ctx.team, ctx.activity)}"]|, "Photos")

    assert has_element?(
             lv,
             "#ask-lead",
             "Coast Range SAR emails each member who attended a link to add their photos. It needs no login."
           )

    assert has_element?(lv, "#ask-to-#{ctx.cam.id}", "Cameron Ruiz")
    assert has_element?(lv, "#ask-to-#{ctx.noor.id}", "Noor Aziz")
    assert has_element?(lv, "#left-out-added", "Added photos: Eli Haddad.")
    assert has_element?(lv, "#left-out-no_email", "No email: Jordan Lee.")
    assert has_element?(lv, "#left-out-asks_off", "Turned photo asks off: Riley Okafor.")
    # Who did not attend is not on either list.
    refute has_element?(lv, "#ask-to-#{ctx.absent.id}")
    refute render(lv) =~ "Sam Rivera"

    assert has_element?(lv, ~s|label[for="ask-message"]|, "Message (optional)")
    assert has_element?(lv, "#ask-form", "Your own words, at the top of the email.")
    assert has_element?(lv, ~s|#ask-message[maxlength="300"]|)
    assert has_element?(lv, "#ask-send[phx-disable-with='Sending…']", "Ask 2 members")
    assert has_element?(lv, ~s|#ask-cancel[href="#{tab(ctx.team, ctx.activity)}"]|, "Cancel")
  end

  test "sending asks each of them, and the tab says when", ctx do
    {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, ctx.activity))

    {:ok, tab, _html} =
      lv
      |> form("#ask-form", %{"message" => "Thanks for coming out!"})
      |> render_submit()
      |> follow_redirect(ctx.conn, tab(ctx.team, ctx.activity))

    assert render(tab) =~ "2 members asked."

    asks = Repo.all(ActivityPhotoAsk)
    assert asks |> Enum.map(& &1.member_id) |> Enum.sort() == Enum.sort([ctx.cam.id, ctx.noor.id])
    assert Enum.all?(asks, &(&1.message == "Thanks for coming out!"))

    today = Format.date_short(DateTime.utc_now(), ctx.team.timezone)
    assert has_element?(tab, "#photos-asked", "Asked 2 members on #{today}.")

    # Asking again reaches whoever still has added none.
    activity_photo_fixture(ctx.activity, %{member_id: ctx.cam.id})
    {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, ctx.activity))
    assert has_element?(lv, "#ask-send", "Ask 1 member")
    assert has_element?(lv, "#left-out-added", "Added photos: Cameron Ruiz and Eli Haddad.")
  end

  test "with nobody to ask it says so, and has no send", ctx do
    for member <- [ctx.cam, ctx.noor],
        do: activity_photo_fixture(ctx.activity, %{member_id: member.id})

    {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, ctx.activity))

    assert has_element?(
             lv,
             "#ask-nobody",
             "Everyone who attended has added photos or cannot be emailed."
           )

    refute has_element?(lv, "#ask-send")
    refute has_element?(lv, "#ask-message")
  end

  test "a message too long says so, and nobody is asked", ctx do
    {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, ctx.activity))

    html = render_submit(lv, "send", %{"message" => String.duplicate("a", 301)})

    assert html =~ "Message must be 300 characters or fewer."
    assert Repo.all(ActivityPhotoAsk) == []
  end

  test "is not found for an incident, an activity still to start, or another team's", ctx do
    incident = activity_fixture(ctx.team, %{activity_kind: "incident"})
    assert_error_sent 404, fn -> live(ctx.conn, ask_path(ctx.team, incident)) end

    coming = activity_fixture(ctx.team, %{started_at: DateTime.add(DateTime.utc_now(), 1, :day)})
    assert_error_sent 404, fn -> live(ctx.conn, ask_path(ctx.team, coming)) end

    theirs = activity_fixture(team_fixture(%{photos_enabled: true}))
    assert_error_sent 404, fn -> live(ctx.conn, ask_path(ctx.team, theirs)) end
  end

  test "a member cannot open it", ctx do
    conn = log_in_user(build_conn(), user_fixture(%{email: ctx.cam.email}))

    assert_error_sent 404, fn -> live(conn, ask_path(ctx.team, ctx.activity)) end
  end
end
