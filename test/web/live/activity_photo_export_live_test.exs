defmodule Web.ActivityPhotoExportLiveTest do
  use Web.ConnCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.FileStore
  alias App.Model.ActivityPhoto
  alias App.Repo

  # Export for a post (#1032, part 9): a team admin picks a shape, places the box, and
  # downloads a JPEG at the shape's size, with the caption ready to copy.
  setup %{conn: conn} do
    team = member_logins_team_fixture(%{name: "Coast Range SAR", photos_enabled: true})
    admin = user_fixture()
    manager_fixture(team, %{email: admin.email, name: "Alex Chen"})
    cam = member_fixture(team, %{name: "Cameron Ruiz", d4h_permission: 2})
    activity = activity_fixture(team, %{title: "Swiftwater training"})

    photo =
      activity_photo_fixture(activity, %{
        member_id: cam.id,
        status: :accepted,
        may_post: true,
        caption: "Throw bag practice at Cedar Creek."
      })

    %{conn: conn, team: team, admin: admin, cam: cam, activity: activity, photo: photo}
  end

  defp export(team, photo), do: ~p"/teams/#{team}/photos/#{photo.id}/export"
  defp file(team, photo), do: ~p"/teams/#{team}/photos/#{photo.id}/export/file"
  defp page(team, photo), do: ~p"/teams/#{team}/photos/#{photo.id}"

  defp as_admin(ctx), do: log_in_user(ctx.conn, ctx.admin)

  describe "the page, for a team admin" do
    test "shows the shapes, the box over the photo, the caption, and the buttons", ctx do
      {:ok, lv, _html} = live(as_admin(ctx), export(ctx.team, ctx.photo))

      assert page_title(lv) =~ "Export for a post"
      assert has_element?(lv, "h1", "Export for a post")
      assert has_element?(lv, "#side-nav-photos[aria-current=page]")
      assert render(lv) =~ "Pick the shape the post needs, place the box, and download."

      assert has_element?(lv, "#photo-shape-choices legend", "Shape")
      assert has_element?(lv, "#photo-shape-choices", "Portrait 4:5")
      assert has_element?(lv, "#photo-shape-choices", "1080 × 1350 · Instagram feed")
      assert has_element?(lv, "#photo-shape-choices", "1920 × 1080 · Facebook, website, YouTube")
      # Original is the photo as edited, 60 × 40.
      assert has_element?(lv, "#photo-shape-choices", "60 × 40 · Anywhere")
      assert has_element?(lv, ~s|#photo-shape-choices input[value="square"][checked]|)

      assert has_element?(
               lv,
               ~s|#photo-export-box-square-wrap[phx-hook="PhotoPlace"][data-ratio="1.0"]|
             )

      assert has_element?(
               lv,
               ~s|#photo-export-box-square img[src*="/photos/#{ctx.photo.id}/file?size=show"]|
             )

      assert has_element?(
               lv,
               "#photo-export-hint",
               "Drag the box to move it. Pinch or scroll to zoom."
             )

      assert has_element?(
               lv,
               "#photo-caption-text",
               "Throw bag practice at Cedar Creek. Photo: Cameron Ruiz"
             )

      assert has_element?(
               lv,
               ~s|#photo-caption-copy[value="Throw bag practice at Cedar Creek. Photo: Cameron Ruiz"]|
             )

      assert has_element?(lv, "#photo-caption", "With credit to who took it.")

      assert has_element?(
               lv,
               ~s|form#photo-export[method=get][action="#{file(ctx.team, ctx.photo)}"]|
             )

      assert has_element?(lv, "#photo-download[type=submit]", "Download JPEG")
      assert has_element?(lv, ~s|#photo-cancel[href="#{page(ctx.team, ctx.photo)}"]|, "Cancel")
    end

    test "a new shape starts a new box of that shape", ctx do
      {:ok, lv, _html} = live(as_admin(ctx), export(ctx.team, ctx.photo))

      lv |> element("#photo-export") |> render_change(%{"shape" => "story"})
      assert has_element?(lv, ~s|#photo-export-box-story-wrap[data-ratio="0.5625"]|)
      refute has_element?(lv, "#photo-export-box-square-wrap")

      lv |> element("#photo-export") |> render_change(%{"shape" => "original"})
      assert has_element?(lv, ~s|#photo-export-box-original-wrap[data-ratio="1.5"]|)
    end

    test "with no caption, the credit alone", ctx do
      ctx.photo |> Ecto.Changeset.change(caption: nil) |> Repo.update!()
      {:ok, lv, _html} = live(as_admin(ctx), export(ctx.team, ctx.photo))
      assert has_element?(lv, "#photo-caption-text", "Photo: Cameron Ruiz")
      refute render(lv) =~ "Throw bag"
    end

    test "a photo the team may not post opens its page, which says why", ctx do
      ctx.photo |> Ecto.Changeset.change(may_post: false) |> Repo.update!()
      to = page(ctx.team, ctx.photo)

      assert {:error, {:live_redirect, %{to: ^to, flash: flash}}} =
               live(as_admin(ctx), export(ctx.team, ctx.photo))

      assert flash["error"] == "Cameron did not give permission to post this photo."
    end

    test "a waiting photo, another team's, and an id that is not one, are not found", ctx do
      waiting = activity_photo_fixture(ctx.activity, %{member_id: ctx.cam.id, may_post: true})
      assert_raise Ecto.NoResultsError, fn -> live(as_admin(ctx), export(ctx.team, waiting)) end

      other = team_fixture(%{photos_enabled: true})

      theirs =
        other
        |> activity_fixture()
        |> activity_photo_fixture(%{status: :accepted, may_post: true})

      assert_raise Ecto.NoResultsError, fn -> live(as_admin(ctx), export(ctx.team, theirs)) end

      assert_raise Web.Status.NotFound, fn ->
        live(as_admin(ctx), ~p"/teams/#{ctx.team}/photos/1x/export")
      end
    end
  end

  describe "the photo's page" do
    test "Actions has Export for a post", ctx do
      {:ok, lv, _html} = live(as_admin(ctx), page(ctx.team, ctx.photo))

      assert has_element?(
               lv,
               ~s|#photo-actions #photo-export[href="#{export(ctx.team, ctx.photo)}"]|,
               "Export for a post"
             )

      refute has_element?(lv, "#photo-export-off")
    end

    test "on a photo the team may not post, the action is greyed and says why", ctx do
      ctx.photo |> Ecto.Changeset.change(may_post: false) |> Repo.update!()
      {:ok, lv, _html} = live(as_admin(ctx), page(ctx.team, ctx.photo))

      refute has_element?(lv, "#photo-export")
      assert has_element?(lv, "#photo-actions #photo-export-off", "Export for a post")

      assert has_element?(
               lv,
               "#photo-export-off",
               "Cameron did not give permission to post this photo."
             )
    end
  end

  describe "Download JPEG" do
    test "gives the box's part of the photo at the shape's size, and saves nothing", ctx do
      before = for {_size, key} <- ActivityPhoto.keys(ctx.photo), do: FileStore.get(key)

      conn =
        get(as_admin(ctx), file(ctx.team, ctx.photo), %{
          "shape" => "landscape",
          "photo" => %{"x" => "0.5", "y" => "0.5", "side" => "1.0"}
        })

      assert response_content_type(conn, :jpeg) =~ "image/jpeg"

      assert get_resp_header(conn, "content-disposition") |> hd() =~
               "photo-#{ctx.photo.id}-landscape.jpg"

      image = conn |> response(200) |> Image.from_binary!()
      # A 60 × 40 original is too small for 1920 × 1080: its whole width, at 16:9.
      assert {Image.width(image), Image.height(image)} == {60, 34}

      assert Repo.reload(ctx.photo) == ctx.photo
      assert for({_size, key} <- ActivityPhoto.keys(ctx.photo), do: FileStore.get(key)) == before
    end

    test "with no box sent, the middle, zoomed all the way out", ctx do
      conn = get(as_admin(ctx), file(ctx.team, ctx.photo), %{"photo" => "nope"})
      image = conn |> response(200) |> Image.from_binary!()
      assert {Image.width(image), Image.height(image)} == {40, 40}
    end

    test "a photo the team may not post, another team's, and a member, are not found", ctx do
      no = activity_photo_fixture(ctx.activity, %{status: :accepted, may_post: false})
      assert_raise Web.Status.NotFound, fn -> get(as_admin(ctx), file(ctx.team, no)) end

      other = team_fixture(%{photos_enabled: true})

      theirs =
        other
        |> activity_fixture()
        |> activity_photo_fixture(%{status: :accepted, may_post: true})

      assert_raise Ecto.NoResultsError, fn -> get(as_admin(ctx), file(ctx.team, theirs)) end

      member = user_fixture(%{email: Repo.reload(ctx.cam).email})
      conn = log_in_user(ctx.conn, member)
      assert_raise Web.Status.NotFound, fn -> get(conn, file(ctx.team, ctx.photo)) end
    end
  end

  test "a member cannot open Export for a post", ctx do
    member = user_fixture(%{email: Repo.reload(ctx.cam).email})
    conn = log_in_user(ctx.conn, member)

    assert_raise Web.Status.NotFound, fn -> live(conn, export(ctx.team, ctx.photo)) end
  end
end
