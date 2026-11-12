defmodule Web.ActivityPhotosOffTest do
  # Not async: it turns the file store off, which is the app's config.
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Activity
  alias App.Operation.AddActivityPhotos

  # With no file store, which is production until storage in Canada exists, a team has
  # no activity photos anywhere (#1032): no tab, no pages, no file, and no counts.
  # Member photos (#1028) go on as before.
  setup %{conn: conn} do
    team = member_logins_team_fixture(%{photos_enabled: true})
    admin = user_fixture()
    manager_fixture(team, %{email: admin.email})
    cam = member_fixture(team, %{name: "Cameron Ruiz", d4h_permission: 2})
    activity = activity_fixture(team, %{title: "Swiftwater training"})
    attendance_fixture(activity, cam)
    # Photos from before the store went: nothing shows them or counts them.
    waiting = activity_photo_fixture(activity, %{member_id: cam.id})
    accepted = activity_photo_fixture(activity, %{member_id: cam.id, status: :accepted})

    App.FileStoreOff.turn_off()

    %{
      conn: conn,
      team: team,
      admin: log_in_user(conn, admin),
      member: log_in_user(conn, user_fixture(%{email: cam.email})),
      cam: cam,
      activity: activity,
      waiting: waiting,
      accepted: accepted
    }
  end

  test "the one test every page asks says no", %{team: team, activity: activity, cam: cam} do
    refute AddActivityPhotos.available?(team)
    activity = Activity.put_logged_minutes(activity)
    now = DateTime.utc_now()

    refute AddActivityPhotos.may_add?(team, activity, %{team_admin?: true, member: nil}, now)
    refute AddActivityPhotos.may_add?(team, activity, %{team_admin?: false, member: cam}, now)
  end

  test "an activity has no Photos tab, and its pages are not found", ctx do
    %{team: team, activity: activity} = ctx
    tab = ~p"/teams/#{team}/activities/#{activity.id}/photos"

    for conn <- [ctx.admin, ctx.member] do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
      refute has_element?(lv, ~s|nav.tabs a[href="#{tab}"]|)
      refute has_element?(lv, "nav.tabs a", "Photos")

      assert_error_sent 404, fn -> get(conn, tab) end
      assert_error_sent 404, fn -> get(conn, tab <> "/new") end
    end
  end

  test "no photo's file is served, waiting or accepted", ctx do
    %{team: team} = ctx

    for conn <- [ctx.admin, ctx.member], photo <- [ctx.waiting, ctx.accepted] do
      assert_error_sent 404, fn -> get(conn, ~p"/teams/#{team}/photos/#{photo.id}/file") end
    end
  end

  test "nothing counts a waiting photo: not Needs attention, not Photos", ctx do
    %{team: team, cam: cam} = ctx

    {:ok, lv, _html} = live(ctx.admin, ~p"/teams/#{team}")
    refute has_element?(lv, "#attention-photos")

    {:ok, lv, _html} = live(ctx.admin, ~p"/teams/#{team}/photos?view=waiting")
    assert has_element?(lv, "#photos-view-waiting", "0")
    assert has_element?(lv, "#no-photos-waiting", "Photos members add of themselves show here")
    refute has_element?(lv, "#activity-photo-#{ctx.waiting.id}")

    # A member's own photo still waits and still counts.
    member_photo_fixture(cam)
    {:ok, lv, _html} = live(ctx.admin, ~p"/teams/#{team}")
    assert has_element?(lv, "#attention-photos", "1 photo waiting")
    assert has_element?(lv, "#attention-photos", "Check it, then accept or decline it.")
  end

  # Photos as it was before activity photos (#1033): the members' three views for a team
  # admin, and a member's own photo alone, with no counts.
  test "Photos has none of the activity photo views, and opens as before", ctx do
    %{team: team} = ctx

    {:ok, lv, _html} = live(ctx.admin, ~p"/teams/#{team}/photos")
    assert has_element?(lv, "#photos-view-members[aria-current=page]")

    for view <- ~w(best activities stars yours),
        do: refute(has_element?(lv, "#photos-view-#{view}"))

    assert has_element?(lv, "#photo-add", "Add a photo")
    refute has_element?(lv, "#photos-add")

    {:ok, lv, _html} = live(ctx.member, ~p"/teams/#{team}/photos")
    assert has_element?(lv, "#your-photo h2", "Your photo")
    refute has_element?(lv, "#photos-switch")
    refute has_element?(lv, "#photos-added")
    refute has_element?(lv, "#photos-add")

    for conn <- [ctx.admin, ctx.member], view <- ~w(best activities stars) do
      assert_raise Web.Status.NotFound, fn ->
        live(conn, ~p"/teams/#{team}/photos?#{[view: view]}")
      end
    end
  end

  test "a photo's page and Add photos are not found", ctx do
    %{team: team} = ctx

    for conn <- [ctx.admin, ctx.member] do
      assert_error_sent 404, fn -> get(conn, ~p"/teams/#{team}/photos/#{ctx.accepted.id}") end
      assert_error_sent 404, fn -> get(conn, ~p"/teams/#{team}/photos/new") end
    end
  end

  test "an activity's Overview shows no photos, no link, and no Add photos", ctx do
    ctx.accepted |> Ecto.Changeset.change(featured_at: DateTime.utc_now()) |> App.Repo.update!()

    for conn <- [ctx.admin, ctx.member] do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
      refute has_element?(lv, "#activity-featured")
      refute has_element?(lv, "#activity-photos-row")
    end
  end
end
