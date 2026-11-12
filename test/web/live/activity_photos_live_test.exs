defmodule Web.ActivityPhotosLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

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
      assert has_element?(lv, "#photo-#{accepted.id}", "Cameron Ruiz · Nov 3, 2026")

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
end
