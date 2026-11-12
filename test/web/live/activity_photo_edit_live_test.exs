defmodule Web.ActivityPhotoEditLiveTest do
  # Not async: Clean up's mode is the app's config.
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.CleanUpStandIn
  alias App.Model.ActivityPhoto
  alias App.Operation.EditActivityPhoto
  alias App.Repo

  # Edit photo (#1032, part 8): a team admin fixes an accepted photo with quarter turns,
  # Straighten, and Clean up. The photo's page then says who edited it, with Revert to
  # original.
  setup %{conn: conn} do
    team = member_logins_team_fixture(%{name: "Coast Range SAR", photos_enabled: true})
    admin = user_fixture()
    manager_fixture(team, %{email: admin.email, name: "Alex Chen"})
    cam = member_fixture(team, %{name: "Cameron Ruiz", d4h_permission: 2})

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
        inserted_at: ~U[2026-10-29 03:00:00.000000Z]
      })

    %{conn: conn, team: team, admin: admin, cam: cam, activity: activity, photo: photo}
  end

  defp edit(team, photo), do: ~p"/teams/#{team}/photos/#{photo.id}/edit"
  defp page(team, photo), do: ~p"/teams/#{team}/photos/#{photo.id}"

  defp as_admin(ctx), do: log_in_user(ctx.conn, ctx.admin)

  defp style(lv),
    do:
      lv
      |> element("#photo-edit")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("style")
      |> hd()

  describe "for a team admin" do
    test "shows the photo as the team will see it, the tools, and the photo as taken", ctx do
      {:ok, lv, _html} = live(as_admin(ctx), edit(ctx.team, ctx.photo))

      assert page_title(lv) =~ "Edit photo"
      assert has_element?(lv, "h1", "Edit photo")
      assert has_element?(lv, "#side-nav-photos[aria-current=page]")

      assert has_element?(
               lv,
               ~s|.breadcrumbs a[href="#{page(ctx.team, ctx.photo)}"]|,
               "Photo from Swiftwater training"
             )

      assert has_element?(
               lv,
               ~s|#photo-edit-image[src*="/photos/#{ctx.photo.id}/file?size=original"]|
             )

      assert has_element?(lv, "#photo-edit .photo-edit-grid")
      assert has_element?(lv, "#photo-rotate-left", "Rotate left")
      assert has_element?(lv, "#photo-rotate-right", "Rotate right")
      assert has_element?(lv, ~s|#photo-angle[type=range][min="-10"][max="10"][step="0.5"]|)
      assert has_element?(lv, "#photo-straighten", "−10°")
      assert has_element?(lv, "#photo-activity", "Swiftwater training")
      assert has_element?(lv, "#photo-added", "Cameron Ruiz, Oct 28, 2026")
      assert has_element?(lv, ~s|#photo-as-taken[src*="size=original"]|)

      assert render(lv) =~
               "Cameron&#39;s original stays as it came, and Revert to original brings it back."

      assert has_element?(lv, "#photo-save", "Save")
      assert has_element?(lv, ~s|#photo-cancel[href="#{page(ctx.team, ctx.photo)}"]|, "Cancel")
    end

    test "with Clean up off, there is no switch", ctx do
      {:ok, lv, _html} = live(as_admin(ctx), edit(ctx.team, ctx.photo))
      refute has_element?(lv, "#photo-clean-up")
    end

    test "Rotate and Straighten turn the photo on the page", ctx do
      {:ok, lv, _html} = live(as_admin(ctx), edit(ctx.team, ctx.photo))
      assert style(lv) =~ "--photo-turn: 0.0deg"
      assert style(lv) =~ "--photo-ratio: 60 / 40"

      lv |> element("#photo-rotate-right") |> render_click()
      assert style(lv) =~ "--photo-turn: 90.0deg"
      assert style(lv) =~ "--photo-ratio: 40 / 60"

      lv |> element("#photo-straighten") |> render_change(%{"angle" => "-3.5"})
      assert style(lv) =~ "--photo-turn: 86.5deg"
      assert has_element?(lv, ~s|#photo-angle[aria-valuetext="−3.5°"]|)

      lv |> element("#photo-rotate-left") |> render_click()
      lv |> element("#photo-rotate-left") |> render_click()
      assert style(lv) =~ "--photo-turn: -93.5deg" or style(lv) =~ "--photo-turn: 266.5deg"
    end

    test "Save keeps the settings, makes the copies again, and opens the photo's page", ctx do
      {:ok, lv, _html} = live(as_admin(ctx), edit(ctx.team, ctx.photo))
      lv |> element("#photo-rotate-left") |> render_click()
      lv |> element("#photo-straighten") |> render_change(%{"angle" => "2"})

      {:ok, page_lv, html} =
        lv
        |> element("#photo-save")
        |> render_click()
        |> follow_redirect(ctx.conn |> log_in_user(ctx.admin), page(ctx.team, ctx.photo))

      assert html =~ "Photo saved."
      saved = Repo.reload(ctx.photo)
      assert {saved.turns, saved.angle, saved.clean_up} == {3, 2.0, false}
      assert has_element?(page_lv, "#photo-edited", "Edited by Alex Chen, Nov")
      # The page holds the turned shape.
      assert has_element?(page_lv, ~s|#photo-image[width="40"][height="60"]|)
    end

    test "starts from the photo's last edit", ctx do
      ctx.photo |> Ecto.Changeset.change(turns: 2, angle: 1.5) |> Repo.update!()
      {:ok, lv, _html} = live(as_admin(ctx), edit(ctx.team, ctx.photo))
      assert style(lv) =~ "--photo-turn: 181.5deg"
      assert has_element?(lv, ~s|#photo-angle[value="1.5"]|)
    end

    test "a waiting photo opens its activity's Photos tab", ctx do
      waiting = activity_photo_fixture(ctx.activity, %{member_id: ctx.cam.id})
      tab = ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/photos"

      assert {:error, {:live_redirect, %{to: ^tab, flash: flash}}} =
               live(as_admin(ctx), edit(ctx.team, waiting))

      assert flash["error"] == "Accept the photo first."
    end

    test "another team's photo, and an id that is not one, are not found", ctx do
      other = team_fixture(%{photos_enabled: true})
      theirs = other |> activity_fixture() |> activity_photo_fixture(%{status: :accepted})

      assert_raise Ecto.NoResultsError, fn -> live(as_admin(ctx), edit(ctx.team, theirs)) end

      assert_raise Web.Status.NotFound, fn ->
        live(as_admin(ctx), ~p"/teams/#{ctx.team}/photos/1x/edit")
      end
    end
  end

  describe "Clean up" do
    test "the switch shows the cleaned-up photo, and Save keeps it on", ctx do
      CleanUpStandIn.turn_on()
      {:ok, lv, _html} = live(as_admin(ctx), edit(ctx.team, ctx.photo))

      assert has_element?(lv, "#photo-clean-up:not([checked])")
      assert render(lv) =~ "Turn it off to keep the photo as Cameron took it."

      lv |> element("#photo-clean-up") |> render_click()
      render_async(lv)
      assert has_element?(lv, ~s|#photo-edit-image[src^="data:image/jpeg;base64,"]|)

      {:ok, _page, html} =
        lv
        |> element("#photo-save")
        |> render_click()
        |> follow_redirect(as_admin(ctx), page(ctx.team, ctx.photo))

      assert html =~ "Photo saved."
      assert Repo.reload(ctx.photo).clean_up
    end

    test "when it does not answer, the photo saves without it and says so", ctx do
      CleanUpStandIn.turn_on()
      {:ok, lv, _html} = live(as_admin(ctx), edit(ctx.team, ctx.photo))
      lv |> element("#photo-clean-up") |> render_click()
      render_async(lv)

      CleanUpStandIn.turn_on(answer: fn _jpeg, :activity -> {:error, :no_function} end)

      lv |> element("#photo-save") |> render_click()
      flash = assert_redirect(lv, page(ctx.team, ctx.photo))
      assert flash["error"] == "Clean up did not answer. The photo is saved without it."
      refute Repo.reload(ctx.photo).clean_up
    end

    test "a preview that does not answer turns the switch off again", ctx do
      CleanUpStandIn.turn_on(answer: fn _jpeg, :activity -> {:error, :no_function} end)
      {:ok, lv, _html} = live(as_admin(ctx), edit(ctx.team, ctx.photo))

      lv |> element("#photo-clean-up") |> render_click()
      assert render_async(lv) =~ "Clean up did not answer."
      assert has_element?(lv, "#photo-clean-up:not([checked])")
    end
  end

  describe "the photo's page" do
    test "Actions has Edit photo for a team admin", ctx do
      {:ok, lv, _html} = live(as_admin(ctx), page(ctx.team, ctx.photo))

      assert has_element?(
               lv,
               ~s|#photo-actions #photo-edit[href="#{edit(ctx.team, ctx.photo)}"]|,
               "Edit photo"
             )

      refute has_element?(lv, "#photo-edited")
    end

    test "an edited photo says who edited it, and Revert to original brings it back", ctx do
      {:ok, edited} =
        EditActivityPhoto.call(
          ctx.team,
          ctx.photo,
          %{turns: 1, angle: 0, clean_up: false},
          ctx.admin,
          ~U[2026-11-12 18:00:00.000000Z]
        )

      {:ok, lv, _html} = live(as_admin(ctx), page(ctx.team, ctx.photo))
      assert has_element?(lv, "#photo-edited", "Edited by Alex Chen, Nov 12, 2026")

      assert lv |> element("#photo-revert") |> render_click() =~ "Photo reverted to the original."
      refute has_element?(lv, "#photo-edited")

      reverted = Repo.reload(edited)
      assert {reverted.turns, reverted.edited_at} == {0, nil}
      assert ActivityPhoto.shown_size(reverted) == {60, 40}
    end

    test "a member sees who edited it, with no Revert and no Edit photo", ctx do
      ctx.photo
      |> Ecto.Changeset.change(
        turns: 1,
        edited_at: ~U[2026-11-12 18:00:00.000000Z],
        edited_by_user_id: ctx.admin.id
      )
      |> Repo.update!()

      member = user_fixture(%{email: Repo.reload(ctx.cam).email})
      {:ok, lv, _html} = ctx.conn |> log_in_user(member) |> live(page(ctx.team, ctx.photo))

      assert has_element?(lv, "#photo-edited", "Edited by Alex Chen, Nov 12, 2026")
      refute has_element?(lv, "#photo-revert")
      refute has_element?(lv, "#photo-edit")
    end
  end

  test "a member cannot open Edit photo", ctx do
    member = user_fixture(%{email: Repo.reload(ctx.cam).email})
    conn = log_in_user(ctx.conn, member)

    assert_raise Web.Status.NotFound, fn -> live(conn, edit(ctx.team, ctx.photo)) end
  end
end
