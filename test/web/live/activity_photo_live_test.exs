defmodule Web.ActivityPhotoLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Ecto.Query, only: [where: 2]
  import Phoenix.LiveViewTest

  alias App.Model.ActivityPhoto
  alias App.Model.ActivityPhotoStar
  alias App.Operation.StarActivityPhoto
  alias App.Repo

  # cspell:ignore Noor -- Noor Aziz, of the Coast Range SAR cast
  # One photo (#1033): an accepted activity photo's page, for everyone on the team.
  # Everyone stars it, and a team admin features, downloads, and deletes it.
  setup %{conn: conn} do
    team = member_logins_team_fixture(%{name: "Coast Range SAR", photos_enabled: true})
    admin = user_fixture()
    manager_fixture(team, %{email: admin.email, name: "Alex Chen"})
    cam = member_fixture(team, %{name: "Cameron Ruiz", d4h_permission: 2})
    noor = member_fixture(team, %{name: "Noor Aziz", d4h_permission: 2})

    activity =
      activity_fixture(team, %{
        title: "Swiftwater training",
        started_at: ~U[2026-10-28 02:00:00Z],
        finished_at: ~U[2026-10-28 04:30:00Z]
      })

    photo =
      activity_photo_fixture(activity, %{
        member_id: cam.id,
        status: :accepted,
        caption: "Throw bag practice at Cedar Creek.",
        may_post: true,
        inserted_at: ~U[2026-10-29 03:00:00.000000Z]
      })

    %{conn: conn, team: team, admin: admin, cam: cam, noor: noor, activity: activity, photo: photo}
  end

  # Logged in as the member: their email is their login.
  defp as(conn, %{email: email}),
    do: log_in_user(conn, App.Accounts.get_user_by_email(email) || user_fixture(%{email: email}))

  defp page(team, photo), do: ~p"/teams/#{team}/photos/#{photo.id}"
  defp stars(photo),
    do: Repo.aggregate(where(ActivityPhotoStar, activity_photo_id: ^photo.id), :count)

  describe "for a member" do
    test "the page shows the photo, who added it, its activity, and what it is for", ctx do
      %{team: team, photo: photo, activity: activity} = ctx

      {:ok, lv, _html} = ctx.conn |> as(ctx.noor) |> live(page(team, photo))

      assert page_title(lv) =~ "Photo from Swiftwater training"
      assert has_element?(lv, "h1", "Photo from Swiftwater training")
      assert has_element?(lv, "#side-nav-photos[aria-current=page]")
      assert has_element?(lv, ~s|.breadcrumbs a[href="#{~p"/teams/#{team}/photos"}"]|, "Photos")

      assert has_element?(
               lv,
               ~s|#photo-image[src*="/photos/#{photo.id}/file?size=show"][alt="Throw bag practice at Cedar Creek."]|
             )

      assert has_element?(lv, "#photo-added", "Cameron Ruiz, Oct 28, 2026")
      tab = ~p"/teams/#{team}/activities/#{activity.id}/photos"
      assert has_element?(lv, ~s|#photo-activity[href="#{tab}"]|, "Swiftwater training")
      assert has_element?(lv, "#photo-caption", "Throw bag practice at Cedar Creek.")
      assert has_element?(lv, "#photo-posting", "Coast Range SAR may post it.")

      # Nothing of a team admin's.
      refute has_element?(lv, "#photo-actions")
      refute has_element?(lv, "#photo-featured")
    end

    test "a photo with no caption, kept for the team, says so", ctx do
      plain = activity_photo_fixture(ctx.activity, %{member_id: ctx.cam.id, status: :accepted})

      {:ok, lv, _html} = ctx.conn |> as(ctx.noor) |> live(page(ctx.team, plain))

      refute has_element?(lv, "#photo-caption")
      assert has_element?(lv, "#photo-posting", "For the team only.")
      assert has_element?(lv, ~s|#photo-image[alt="Photo from Swiftwater training"]|)
    end

    test "Star gives one star, and Starred takes it back", ctx do
      {:ok, lv, _html} = ctx.conn |> as(ctx.noor) |> live(page(ctx.team, ctx.photo))

      assert has_element?(lv, "#photo-star[aria-pressed=false]", "Star")
      assert has_element?(lv, "#photo-stars", "0")

      lv |> element("#photo-star") |> render_click()

      assert has_element?(lv, "#photo-star[aria-pressed=true]", "Starred")
      assert has_element?(lv, "#photo-stars", "1")
      assert stars(ctx.photo) == 1

      # Open again: still one, and theirs.
      {:ok, lv, _html} = ctx.conn |> as(ctx.noor) |> live(page(ctx.team, ctx.photo))
      assert has_element?(lv, "#photo-star[aria-pressed=true]", "Starred")

      lv |> element("#photo-star") |> render_click()

      assert has_element?(lv, "#photo-star[aria-pressed=false]", "Star")
      assert has_element?(lv, "#photo-stars", "0")
      assert stars(ctx.photo) == 0
    end

    test "the count is everyone's, and nothing says who starred", ctx do
      {:ok, true} = StarActivityPhoto.call(ctx.photo, ctx.admin)
      cam_user = user_fixture(%{email: ctx.cam.email})
      {:ok, true} = StarActivityPhoto.call(ctx.photo, cam_user)

      {:ok, lv, html} = ctx.conn |> as(ctx.noor) |> live(page(ctx.team, ctx.photo))

      assert has_element?(lv, "#photo-star[aria-pressed=false]", "Star")
      assert has_element?(lv, "#photo-stars", "2")
      # Cameron added it, so the page names them once, as who added it. Nobody else.
      refute html =~ "Alex Chen"
      refute html =~ ctx.admin.email
      refute html =~ cam_user.email
      assert html |> String.split("Cameron Ruiz") |> length() == 2
    end

    test "a team admin's events do nothing for a member", ctx do
      {:ok, lv, _html} = ctx.conn |> as(ctx.noor) |> live(page(ctx.team, ctx.photo))

      render_hook(lv, "feature", %{})
      render_hook(lv, "delete", %{})

      assert %ActivityPhoto{featured_at: nil} = Repo.reload(ctx.photo)
    end

    test "a waiting photo has no page, not even for who added it", ctx do
      waiting = activity_photo_fixture(ctx.activity, %{member_id: ctx.cam.id})

      for who <- [ctx.cam, ctx.noor] do
        assert_raise Ecto.NoResultsError, fn ->
          ctx.conn |> as(who) |> live(page(ctx.team, waiting))
        end
      end

      assert_raise Ecto.NoResultsError, fn ->
        ctx.conn |> log_in_user(ctx.admin) |> live(page(ctx.team, waiting))
      end
    end

    test "a photo on an incident or a deleted activity, and an id that is not one, are not found",
         ctx do
      incident = activity_fixture(ctx.team, %{activity_kind: "incident"})
      hidden = activity_photo_fixture(incident, %{status: :accepted})
      gone = activity_fixture(ctx.team, %{deleted_at: ~U[2026-11-01 00:00:00Z]})
      deleted = activity_photo_fixture(gone, %{status: :accepted})
      conn = as(ctx.conn, ctx.noor)

      for photo <- [hidden, deleted],
          do: assert_raise(Ecto.NoResultsError, fn -> live(conn, page(ctx.team, photo)) end)

      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{ctx.team}/photos/1x") end
    end
  end

  describe "for a team admin" do
    setup %{conn: conn, admin: admin}, do: %{conn: log_in_user(conn, admin)}

    test "Actions has Feature, Download original, and Delete photo", ctx do
      {:ok, lv, _html} = live(ctx.conn, page(ctx.team, ctx.photo))

      assert has_element?(lv, "#photo-actions #photo-feature", "Feature")
      refute has_element?(lv, "#photo-stop-featuring")

      assert has_element?(
               lv,
               ~s|#photo-download[href*="/photos/#{ctx.photo.id}/file?size=original"][download]|,
               "Download original"
             )

      assert has_element?(
               lv,
               ~s|#photo-delete[data-confirm="Delete this photo? It is gone for good."][data-confirm-button="Delete photo"]|,
               "Delete photo"
             )
    end

    test "Feature marks it Featured, and Stop featuring takes that back", ctx do
      {:ok, lv, _html} = live(ctx.conn, page(ctx.team, ctx.photo))

      assert lv |> element("#photo-feature") |> render_click() =~ "Photo featured."
      assert has_element?(lv, "#photo-featured", "Featured")
      assert has_element?(lv, "#photo-stop-featuring", "Stop featuring")
      refute has_element?(lv, "#photo-feature")
      assert Repo.reload(ctx.photo).featured_at

      assert lv |> element("#photo-stop-featuring") |> render_click() =~
               "Photo no longer featured."

      refute has_element?(lv, "#photo-featured")
      refute Repo.reload(ctx.photo).featured_at
    end

    test "a third featured photo on the activity is refused, with why", ctx do
      for _ <- 1..2 do
        activity_photo_fixture(ctx.activity, %{
          status: :accepted,
          featured_at: ~U[2026-11-01 00:00:00.000000Z]
        })
      end

      {:ok, lv, _html} = live(ctx.conn, page(ctx.team, ctx.photo))

      lv |> element("#photo-feature") |> render_click()

      # The toast's title is the first sentence, and the rest sits under it.
      assert has_element?(lv, ".toast-error .toast-title", "2 photos are featured already.")
      assert has_element?(lv, ".toast-error .toast-sub", "Stop featuring one first.")
      refute has_element?(lv, "#photo-featured")
      refute Repo.reload(ctx.photo).featured_at
    end

    test "Delete photo takes the photo, its stars, and its files, and opens the tab", ctx do
      {:ok, true} = StarActivityPhoto.call(ctx.photo, ctx.admin)
      {:ok, lv, _html} = live(ctx.conn, page(ctx.team, ctx.photo))

      tab = ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/photos"
      {:ok, _lv, html} = lv |> element("#photo-delete") |> render_click() |> follow_redirect(ctx.conn, tab)

      assert html =~ "Photo deleted."
      refute Repo.reload(ctx.photo)
      assert stars(ctx.photo) == 0
      assert ctx.photo |> activity_photo_files() |> Enum.all?(&(&1 == {:error, :not_found}))
    end

    test "a team admin opens a deleted activity's photo, which a member does not", ctx do
      gone = activity_fixture(ctx.team, %{deleted_at: ~U[2026-11-01 00:00:00Z]})
      deleted = activity_photo_fixture(gone, %{status: :accepted})

      {:ok, lv, _html} = live(ctx.conn, page(ctx.team, deleted))
      assert has_element?(lv, "#photo-delete")
    end
  end

  test "viewing as a member, a star is not saved", ctx do
    conn =
      ctx.conn
      |> log_in_user(ctx.admin)
      |> post(~p"/teams/#{ctx.team}/members/#{ctx.noor}/view-as")
      |> recycle()

    {:ok, lv, _html} = live(conn, page(ctx.team, ctx.photo))

    refute has_element?(lv, "#photo-actions")
    lv |> element("#photo-star") |> render_click()

    assert has_element?(lv, "#photo-stars", "0")
    assert stars(ctx.photo) == 0
  end
end
