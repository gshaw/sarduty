defmodule Web.ActivityPhotosLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Operation.StarActivityPhoto
  alias App.Repo

  # cspell:ignore Noor -- Noor Aziz, of the Coast Range SAR cast
  # An activity's Photos tab (#1032): everyone sees the accepted photos, a member their
  # own waiting ones too, and a team admin accepts or deletes the ones that wait.
  setup %{conn: conn} do
    team = member_logins_team_fixture(%{name: "Coast Range SAR", photos_enabled: true})
    admin = user_fixture()
    manager_fixture(team, %{email: admin.email, name: "Alex Chen"})
    cam = member_fixture(team, %{name: "Cameron Ruiz", d4h_permission: 2})
    noor = member_fixture(team, %{name: "Noor Aziz", d4h_permission: 2})
    started_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

    activity =
      activity_fixture(team, %{
        title: "Swiftwater training",
        started_at: started_at,
        finished_at: DateTime.add(started_at, 2, :hour)
      })

    attendance_fixture(activity, cam)

    %{conn: conn, team: team, admin: admin, cam: cam, noor: noor, activity: activity}
  end

  # Logged in as the member: their email is their login.
  defp as(conn, %{email: email}),
    do: log_in_user(conn, App.Accounts.get_user_by_email(email) || user_fixture(%{email: email}))

  defp tab(team, activity), do: ~p"/teams/#{team}/activities/#{activity.id}/photos"
  defp add(team, activity), do: ~p"/teams/#{team}/activities/#{activity.id}/photos/new"

  defp count(lv, selector),
    do: lv |> render() |> Floki.parse_fragment!() |> Floki.find(selector) |> length()

  defp status(photo), do: Repo.reload!(photo).status

  describe "for a team admin" do
    setup %{conn: conn, admin: admin}, do: %{conn: log_in_user(conn, admin)}

    test "the tab counts the photos waiting, on every tab of the activity", ctx do
      %{conn: conn, team: team, activity: activity, cam: cam} = ctx
      overview = ~p"/teams/#{team}/activities/#{activity.id}"

      {:ok, lv, _html} = live(conn, overview)
      assert has_element?(lv, ~s|nav.tabs a[href="#{tab(team, activity)}"]|, "Photos")
      refute has_element?(lv, ~s|nav.tabs a[href="#{tab(team, activity)}"] .badge|)

      activity_photo_fixture(activity, %{member_id: cam.id})
      activity_photo_fixture(activity, %{member_id: cam.id})
      activity_photo_fixture(activity, %{member_id: cam.id, status: :accepted})

      {:ok, lv, _html} = live(conn, overview)
      assert has_element?(lv, ~s|nav.tabs a[href="#{tab(team, activity)}"] .badge|, "2")

      {:ok, lv, _html} = live(conn, tab(team, activity))
      assert page_title(lv) =~ "Swiftwater training · Photos"
      assert has_element?(lv, ~s|nav.tabs a[aria-current=page] .badge|, "2")
    end

    test "Waiting has every waiting photo as a checked tile, then the accepted ones", ctx do
      %{conn: conn, team: team, activity: activity, cam: cam, noor: noor} = ctx
      first = activity_photo_fixture(activity, %{member_id: cam.id})
      second = activity_photo_fixture(activity, %{member_id: noor.id})

      accepted =
        activity_photo_fixture(activity, %{
          member_id: cam.id,
          status: :accepted,
          caption: "Throw bag practice at Cedar Creek.",
          inserted_at: ~U[2026-11-03 20:00:00.000000Z]
        })

      {:ok, lv, _html} = live(conn, tab(team, activity))

      assert has_element?(lv, "#photos-waiting h2", "Waiting")

      assert has_element?(
               lv,
               "#photos-waiting",
               "Only team admins and the member who added one see it."
             )

      assert count(lv, "#photos-waiting-grid > li") == 2
      assert has_element?(lv, "#photo-#{first.id}-check[checked]")
      assert has_element?(lv, "#photo-#{second.id}-check[checked]")
      assert has_element?(lv, ~s|label[for="photo-#{first.id}-check"]|, "Cameron Ruiz")
      assert has_element?(lv, ~s|label[for="photo-#{second.id}-check"]|, "Noor Aziz")
      assert has_element?(lv, "#photos-checked", "2 checked")
      assert has_element?(lv, "#photos-accept", "Accept 2")
      assert has_element?(lv, "#photos-delete", "Delete")

      # The tile is the 600 px copy, and opens the copy to show.
      assert has_element?(
               lv,
               ~s|#photo-#{first.id}-tile img[src*="/photos/#{first.id}/file?size=tile"]|
             )

      assert has_element?(
               lv,
               ~s|#photo-#{first.id}-tile a[href*="/photos/#{first.id}/file?size=show"]|
             )

      # The accepted ones under their count, each with who added it and when.
      assert has_element?(lv, "#photos-count", "1 photo")
      assert count(lv, "#photos-grid > li") == 1
      assert has_element?(lv, "#photo-#{accepted.id}", "Cameron Ruiz · Nov 3")

      assert has_element?(
               lv,
               ~s|#photo-#{accepted.id}-tile img[alt="Throw bag practice at Cedar Creek."]|
             )

      refute has_element?(lv, "#photo-#{accepted.id}-check")
      refute has_element?(lv, "#photo-#{accepted.id}-waiting")
      assert has_element?(lv, ~s|#photos-add[href="#{add(team, activity)}"]|, "Add photos")
    end

    test "Accept accepts the checked tiles, and a cleared one stays waiting", ctx do
      %{conn: conn, team: team, activity: activity, cam: cam} = ctx

      [first, second, third] =
        for _n <- 1..3, do: activity_photo_fixture(activity, %{member_id: cam.id})

      {:ok, lv, _html} = live(conn, tab(team, activity))

      lv
      |> form("#photos-waiting-form")
      |> render_change(%{"photo_ids" => [to_string(first.id), to_string(third.id)]})

      refute has_element?(lv, "#photo-#{second.id}-check[checked]")
      assert has_element?(lv, "#photos-checked", "2 checked")
      assert has_element?(lv, "#photos-accept", "Accept 2")

      lv
      |> form("#photos-waiting-form")
      |> render_submit(%{"photo_ids" => [to_string(first.id), to_string(third.id)]})

      assert render(lv) =~ "2 photos accepted."
      assert status(first) == :accepted
      assert status(second) == :waiting
      assert status(third) == :accepted

      # The one left is checked again, and the tab counts it.
      assert count(lv, "#photos-waiting-grid > li") == 1
      assert has_element?(lv, "#photo-#{second.id}-check[checked]")
      assert has_element?(lv, "#photos-count", "2 photos")
      assert has_element?(lv, ~s|nav.tabs a[aria-current=page] .badge|, "1")
    end

    test "Delete asks first, then deletes the checked tiles with their files", ctx do
      %{conn: conn, team: team, activity: activity, cam: cam} = ctx

      [first, second, third] =
        for _n <- 1..3, do: activity_photo_fixture(activity, %{member_id: cam.id})

      {:ok, lv, _html} = live(conn, tab(team, activity))

      assert has_element?(
               lv,
               ~s|#photos-delete[data-confirm="Delete 3 photos? They are gone for good."][data-confirm-button="Delete photos"]|
             )

      refute has_element?(lv, "#photos-delete[data-confirm-check]")

      lv
      |> form("#photos-waiting-form")
      |> render_change(%{"photo_ids" => [to_string(second.id)]})

      assert has_element?(
               lv,
               ~s|#photos-delete[data-confirm="Delete 1 photo? It is gone for good."][data-confirm-button="Delete photo"]|
             )

      lv |> element("#photos-delete") |> render_click()

      assert render(lv) =~ "1 photo deleted."
      refute Repo.reload(second)
      assert second |> activity_photo_files() |> Enum.all?(&(&1 == {:error, :not_found}))
      assert status(first) == :waiting
      assert status(third) == :waiting
      assert [{:ok, _original}, {:ok, _show}, {:ok, _tile}] = activity_photo_files(first)
      assert count(lv, "#photos-waiting-grid > li") == 2
    end

    test "from 10 photos, Delete waits on a check box naming the count", ctx do
      %{conn: conn, team: team, activity: activity} = ctx
      for _n <- 1..10, do: activity_photo_fixture(activity)

      {:ok, lv, _html} = live(conn, tab(team, activity))

      assert has_element?(
               lv,
               ~s|#photos-delete[data-confirm-check="I understand 10 photos are gone for good."]|
             )
    end

    test "with nothing checked, Accept and Delete are off", ctx do
      %{conn: conn, team: team, activity: activity} = ctx
      photo = activity_photo_fixture(activity)

      {:ok, lv, _html} = live(conn, tab(team, activity))
      lv |> form("#photos-waiting-form") |> render_change(%{"photo_ids" => []})

      assert has_element?(lv, "#photos-checked", "0 checked")
      assert has_element?(lv, "#photos-accept[disabled]", "Accept")
      assert has_element?(lv, "#photos-delete[disabled]")

      # An event sent anyway changes nothing.
      assert render_hook(lv, "delete-photos", %{}) =~ "Check the photos to delete first."
      assert render_hook(lv, "accept-photos", %{}) =~ "Check the photos to accept first."
      assert status(photo) == :waiting
    end

    test "ids from another activity or another team change nothing", ctx do
      %{conn: conn, team: team, activity: activity} = ctx
      elsewhere = activity_photo_fixture(activity_fixture(team))
      theirs = activity_photo_fixture(activity_fixture(team_fixture(%{photos_enabled: true})))
      activity_photo_fixture(activity)

      {:ok, lv, _html} = live(conn, tab(team, activity))
      ids = [to_string(elsewhere.id), to_string(theirs.id)]

      render_hook(lv, "accept-photos", %{"photo_ids" => ids})
      render_hook(lv, "tick-photos", %{"photo_ids" => ids})
      render_hook(lv, "delete-photos", %{})

      assert status(elsewhere) == :waiting
      assert status(theirs) == :waiting
      assert [{:ok, _original}, {:ok, _show}, {:ok, _tile}] = activity_photo_files(theirs)
    end

    test "a team admin adds once the activity starts, with no photos yet", ctx do
      %{conn: conn, team: team, activity: activity} = ctx

      {:ok, lv, _html} = live(conn, tab(team, activity))
      refute has_element?(lv, "#photos-waiting")
      assert has_element?(lv, "#photos-empty", "No photos yet. Add the first.")
      assert has_element?(lv, ~s|#photos-add[href="#{add(team, activity)}"]|, "Add photos")

      coming = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), 1, :day)})
      {:ok, lv, _html} = live(conn, tab(team, coming))
      assert has_element?(lv, "#photos-empty", "No photos yet.")
      refute has_element?(lv, "#photos-empty", "Add the first.")
      refute has_element?(lv, "#photos-add")
      refute has_element?(lv, "#photos-ask")
    end

    test "Ask for photos sits beside Add photos, and the tab says when the team asked", ctx do
      %{conn: conn, team: team, activity: activity, cam: cam} = ctx
      ask = ~p"/teams/#{team}/activities/#{activity.id}/photos/ask"

      {:ok, lv, _html} = live(conn, tab(team, activity))
      assert has_element?(lv, ~s|#photos-empty #photos-ask[href="#{ask}"]|, "Ask for photos")
      refute has_element?(lv, "#photos-asked")

      activity_photo_fixture(activity, %{member_id: cam.id, status: :accepted})
      noor = Repo.get_by!(App.Model.Member, name: "Noor Aziz", team_id: team.id)
      attendance_fixture(activity, noor)
      asked_at = ~U[2026-11-09 18:00:00.000000Z]

      for member <- [cam, noor] do
        Repo.insert!(%App.Model.ActivityPhotoAsk{
          team_id: team.id,
          activity_id: activity.id,
          member_id: member.id,
          asked_at: asked_at,
          email_status: :sent
        })
      end

      {:ok, lv, _html} = live(conn, tab(team, activity))
      assert has_element?(lv, ~s|#photos-ask[href="#{ask}"]|, "Ask for photos")
      assert has_element?(lv, "#photos-add", "Add photos")
      assert has_element?(lv, "#photos-asked", "Asked 2 members on Nov 9, 2026.")

      # A member sees neither.
      {:ok, lv, _html} = conn |> as(cam) |> live(tab(team, activity))
      refute has_element?(lv, "#photos-ask")
      refute has_element?(lv, "#photos-asked")
    end

    test "an incident and an activity with logged time have no Photos tab", ctx do
      %{conn: conn, team: team} = ctx

      for activity <- [
            activity_fixture(team, %{activity_kind: "incident"}),
            chore_activity_fixture(team, [60])
          ] do
        {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
        refute has_element?(lv, ~s|nav.tabs a[href="#{tab(team, activity)}"]|)
        assert_error_sent 404, fn -> get(conn, tab(team, activity)) end
        assert_error_sent 404, fn -> get(conn, add(team, activity)) end
      end

      # An event takes photos, as an exercise does.
      event = activity_fixture(team, %{activity_kind: "event"})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{event.id}")
      assert has_element?(lv, ~s|nav.tabs a[href="#{tab(team, event)}"]|, "Photos")
    end

    test "with Photos off, no activity has the tab", ctx do
      %{conn: conn, team: team, activity: activity} = ctx
      team |> Ecto.Changeset.change(photos_enabled: false) |> Repo.update!()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
      refute has_element?(lv, ~s|nav.tabs a[href="#{tab(team, activity)}"]|)
      assert_error_sent 404, fn -> get(conn, tab(team, activity)) end
      assert_error_sent 404, fn -> get(conn, add(team, activity)) end
    end

    test "the activity's Delete still works from the tab's page", ctx do
      %{conn: conn, team: team, activity: activity} = ctx
      {:ok, lv, _html} = live(conn, tab(team, activity))
      # A D4H team has no Delete activity, and the event sent anyway does nothing.
      refute has_element?(lv, "#activity-delete")
      render_hook(lv, "delete", %{})
      assert Repo.reload(activity)
    end
  end

  describe "for a member" do
    test "sees the accepted photos and their own waiting ones, marked Waiting", ctx do
      %{conn: conn, team: team, activity: activity, cam: cam, noor: noor} = ctx
      accepted = activity_photo_fixture(activity, %{member_id: noor.id, status: :accepted})
      own = activity_photo_fixture(activity, %{member_id: cam.id})
      hers = activity_photo_fixture(activity, %{member_id: noor.id})

      {:ok, lv, _html} = conn |> as(cam) |> live(tab(team, activity))

      # No Waiting section, no boxes, and no count on the tab: those are a team admin's.
      refute has_element?(lv, "#photos-waiting")
      refute has_element?(lv, "#photos-accept")
      refute has_element?(lv, "input[type=checkbox]")
      refute has_element?(lv, "nav.tabs .badge")

      assert has_element?(lv, "#photos-count", "2 photos")
      assert has_element?(lv, "#photo-#{accepted.id}", "Noor Aziz")
      refute has_element?(lv, "#photo-#{accepted.id}-waiting")
      assert has_element?(lv, "#photo-#{own.id}", "Cameron Ruiz")
      assert has_element?(lv, "#photo-#{own.id}-waiting", "Waiting")

      # Another member's waiting photo is nowhere on the page.
      refute has_element?(lv, "#photo-#{hers.id}")
      refute render(lv) =~ "/photos/#{hers.id}/file"

      # Noor sees hers, and not Cameron's.
      {:ok, lv, _html} = conn |> as(noor) |> live(tab(team, activity))
      assert has_element?(lv, "#photo-#{hers.id}-waiting", "Waiting")
      refute has_element?(lv, "#photo-#{own.id}")
    end

    test "Add photos is for a member who attended", ctx do
      %{conn: conn, team: team, activity: activity, cam: cam, noor: noor} = ctx

      {:ok, lv, _html} = conn |> as(cam) |> live(tab(team, activity))
      assert has_element?(lv, "#photos-empty", "No photos yet. Add the first.")
      assert has_element?(lv, ~s|#photos-add[href="#{add(team, activity)}"]|, "Add photos")

      # Noor did not attend: no button, and no page.
      {:ok, lv, _html} = conn |> as(noor) |> live(tab(team, activity))
      assert has_element?(lv, "#photos-empty", "No photos yet.")
      refute has_element?(lv, "#photos-empty", "Add the first.")
      refute has_element?(lv, "#photos-add")
      assert_error_sent 404, fn -> conn |> as(noor) |> get(add(team, activity)) end
    end

    test "sends none of a team admin's events", ctx do
      %{conn: conn, team: team, activity: activity, cam: cam} = ctx
      own = activity_photo_fixture(activity, %{member_id: cam.id})

      {:ok, lv, _html} = conn |> as(cam) |> live(tab(team, activity))
      ids = %{"photo_ids" => [to_string(own.id)]}

      render_hook(lv, "accept-photos", ids)
      render_hook(lv, "tick-photos", ids)
      render_hook(lv, "delete-photos", %{})

      assert status(own) == :waiting
      assert [{:ok, _original}, {:ok, _show}, {:ok, _tile}] = activity_photo_files(own)
    end

    test "a team admin viewing as a member sees what the member sees, and changes nothing", ctx do
      %{conn: conn, team: team, activity: activity, cam: cam, noor: noor, admin: admin} = ctx
      own = activity_photo_fixture(activity, %{member_id: cam.id})
      hers = activity_photo_fixture(activity, %{member_id: noor.id})

      conn = conn |> log_in_user(admin) |> post(~p"/teams/#{team}/members/#{cam.id}/view-as")
      {:ok, lv, _html} = live(conn, tab(team, activity))

      refute has_element?(lv, "#photos-waiting")
      assert has_element?(lv, "#photo-#{own.id}-waiting", "Waiting")
      refute has_element?(lv, "#photo-#{hers.id}")

      assert render_hook(lv, "accept-photos", %{"photo_ids" => [to_string(own.id)]}) =~
               "viewing as Cameron Ruiz, so nothing is saved"

      assert status(own) == :waiting
    end
  end

  # Stars and featured photos (#1033).
  describe "stars and featured photos" do
    defp accepted(ctx, attrs \\ %{}),
      do:
        activity_photo_fixture(
          ctx.activity,
          Map.merge(%{member_id: ctx.cam.id, status: :accepted}, attrs)
        )

    defp order(lv) do
      lv
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("#photos-grid > li")
      |> Enum.flat_map(&Floki.attribute(&1, "id"))
    end

    test "the tab has the most stars first, each with its count, and yours marked", ctx do
      %{conn: conn, team: team, activity: activity, admin: admin} = ctx
      old = accepted(ctx, %{inserted_at: ~U[2026-11-01 20:00:00.000000Z]})
      new = accepted(ctx, %{inserted_at: ~U[2026-11-03 20:00:00.000000Z]})
      liked = accepted(ctx, %{inserted_at: ~U[2026-11-02 20:00:00.000000Z]})
      cam_user = user_fixture(%{email: ctx.cam.email})
      {:ok, true} = StarActivityPhoto.call(liked, cam_user)
      {:ok, true} = StarActivityPhoto.call(liked, admin)
      {:ok, true} = StarActivityPhoto.call(old, admin)

      {:ok, lv, _html} = conn |> log_in_user(cam_user) |> live(tab(team, activity))

      # 2 stars, then 1, then none.
      assert order(lv) == ["photo-#{liked.id}", "photo-#{old.id}", "photo-#{new.id}"]
      assert has_element?(lv, "#photo-#{liked.id}-tile-stars.is-starred", "2")
      assert has_element?(lv, "#photo-#{liked.id}-tile-stars .icon-star-filled")
      assert has_element?(lv, "#photo-#{old.id}-tile-stars:not(.is-starred)", "1")
      assert has_element?(lv, "#photo-#{new.id}-tile-stars:not(.is-starred)", "0")

      # A tile opens the photo's page.
      page = ~p"/teams/#{team}/photos/#{liked.id}"
      assert has_element?(lv, ~s|#photo-#{liked.id}-tile a[href="#{page}"]|)
    end

    test "a member's own waiting photo has no stars and no page", ctx do
      own = activity_photo_fixture(ctx.activity, %{member_id: ctx.cam.id})

      {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(tab(ctx.team, ctx.activity))

      refute has_element?(lv, "#photo-#{own.id}-tile-stars")
      assert has_element?(lv, ~s|#photo-#{own.id}-tile a[target=_blank]|)
      refute has_element?(lv, ~s|a[href="#{~p"/teams/#{ctx.team}/photos/#{own.id}"}"]|)
    end

    test "a team admin features up to 2 from their tiles, and stops featuring one", ctx do
      %{conn: conn, team: team, activity: activity, admin: admin} = ctx
      [first, second, third] = for _ <- 1..3, do: accepted(ctx)

      {:ok, lv, _html} = conn |> log_in_user(admin) |> live(tab(team, activity))

      assert has_element?(lv, "#photo-#{first.id}-feature", "Feature")
      refute has_element?(lv, "#photo-#{first.id}-featured")

      assert lv |> element("#photo-#{first.id}-feature") |> render_click() =~ "Photo featured."
      lv |> element("#photo-#{second.id}-feature") |> render_click()

      assert has_element?(lv, "#photo-#{first.id}-featured", "Featured")
      assert has_element?(lv, "#photo-#{first.id}-stop-featuring", "Stop featuring")
      refute has_element?(lv, "#photo-#{first.id}-feature")

      # A third is refused, and the toast says why.
      lv |> element("#photo-#{third.id}-feature") |> render_click()
      assert has_element?(lv, ".toast-error .toast-title", "2 photos are featured already.")
      assert has_element?(lv, ".toast-error .toast-sub", "Stop featuring one first.")
      refute Repo.reload(third).featured_at

      assert lv |> element("#photo-#{first.id}-stop-featuring") |> render_click() =~
               "Photo no longer featured."

      lv |> element("#photo-#{third.id}-feature") |> render_click()
      assert Repo.reload(third).featured_at
      refute Repo.reload(first).featured_at
    end

    test "a waiting photo has no Feature, and a photo of another activity is never featured",
         ctx do
      waiting = activity_photo_fixture(ctx.activity, %{member_id: ctx.cam.id})
      elsewhere = activity_photo_fixture(activity_fixture(ctx.team), %{status: :accepted})

      {:ok, lv, _html} =
        ctx.conn |> log_in_user(ctx.admin) |> live(tab(ctx.team, ctx.activity))

      refute has_element?(lv, "#photo-#{waiting.id}-feature")
      render_hook(lv, "feature-photo", %{"id" => to_string(elsewhere.id)})
      render_hook(lv, "feature-photo", %{"id" => to_string(waiting.id)})

      refute Repo.reload(elsewhere).featured_at
      refute Repo.reload(waiting).featured_at
    end

    test "a member sees Featured, and features nothing", ctx do
      featured = accepted(ctx, %{featured_at: ~U[2026-11-04 20:00:00.000000Z]})
      plain = accepted(ctx)

      {:ok, lv, _html} = ctx.conn |> as(ctx.noor) |> live(tab(ctx.team, ctx.activity))

      assert has_element?(lv, "#photo-#{featured.id}-featured", "Featured")
      refute has_element?(lv, "#photo-#{featured.id}-stop-featuring")
      refute has_element?(lv, "#photo-#{plain.id}-feature")

      render_hook(lv, "feature-photo", %{"id" => to_string(plain.id)})
      render_hook(lv, "stop-featuring-photo", %{"id" => to_string(featured.id)})

      refute Repo.reload(plain).featured_at
      assert Repo.reload(featured).featured_at
    end

    test "the Overview shows the featured photos, a link to them all, and Add photos", ctx do
      %{team: team, activity: activity} = ctx
      overview = ~p"/teams/#{team}/activities/#{activity.id}"
      second = accepted(ctx, %{featured_at: ~U[2026-11-04 21:00:00.000000Z]})

      first =
        accepted(ctx, %{
          featured_at: ~U[2026-11-04 20:00:00.000000Z],
          caption: "Throw bag practice at Cedar Creek."
        })

      plain = accepted(ctx)
      # A waiting photo is not counted.
      activity_photo_fixture(activity, %{member_id: ctx.cam.id})

      # Cameron attended, so they add.
      {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(overview)

      ids =
        lv
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("#activity-featured > li")
        |> Enum.flat_map(&Floki.attribute(&1, "id"))

      assert ids == ["featured-#{first.id}", "featured-#{second.id}"]
      refute has_element?(lv, "#featured-#{plain.id}")
      page = ~p"/teams/#{team}/photos/#{first.id}"

      assert has_element?(
               lv,
               ~s|#featured-#{first.id} a[href="#{page}"] img[alt="Throw bag practice at Cedar Creek."]|
             )

      assert has_element?(
               lv,
               ~s|#activity-photos-all[href="#{tab(team, activity)}"]|,
               "All 3 photos"
             )

      assert has_element?(
               lv,
               ~s|#activity-photos-add[href="#{add(team, activity)}"]|,
               "Add photos"
             )

      # Noor did not attend: the photos and the link, and no button.
      {:ok, lv, _html} = ctx.conn |> as(ctx.noor) |> live(overview)
      assert has_element?(lv, "#featured-#{first.id}")
      assert has_element?(lv, "#activity-photos-all", "All 3 photos")
      refute has_element?(lv, "#activity-photos-add")
    end

    test "an Overview with no photos has Add photos alone, for whoever may add", ctx do
      overview = ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}"

      {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(overview)
      refute has_element?(lv, "#activity-featured")
      refute has_element?(lv, "#activity-photos-all")
      assert has_element?(lv, "#activity-photos-add", "Add photos")

      {:ok, lv, _html} = ctx.conn |> as(ctx.noor) |> live(overview)
      refute has_element?(lv, "#activity-photos-row")

      # An incident shows none of it.
      incident = activity_fixture(ctx.team, %{activity_kind: "incident"})

      {:ok, lv, _html} =
        ctx.conn
        |> log_in_user(ctx.admin)
        |> live(~p"/teams/#{ctx.team}/activities/#{incident.id}")

      refute has_element?(lv, "#activity-photos-row")
    end
  end
end
