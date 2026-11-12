defmodule Web.MemberPhotoLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.D4H
  alias App.Model.ChangeSetRow
  alias App.Model.MemberPhoto
  alias App.Model.MemberPhotoFile
  alias App.Operation.AddOwnPhoto
  alias App.Operation.DeclineMemberPhoto
  alias App.RecordsStub
  alias App.Repo

  # Check a photo (#1029): a team admin places a photo a member added again if it needs
  # it, then accepts or declines it.
  setup %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{team: %{photos_enabled: true, d4h_access_key: "team-key"}})

    cam = member_fixture(team, %{name: "Cameron Ruiz", has_photo: true})

    photo =
      member_photo_fixture(cam, %{
        turns: 1,
        x: 0.5,
        y: 0.4,
        side: 0.5,
        inserted_at: ~U[2026-11-12 20:34:00.000000Z]
      })

    %{conn: log_in_user(conn, user), user: user, team: team, cam: cam, photo: photo}
  end

  defp stub_ok do
    RecordsStub.stub(fn _method, _path, _body ->
      {200, %{"id" => 9, "targetResource" => %{"id" => 70}}}
    end)
  end

  defp check_path(team, photo), do: ~p"/teams/#{team}/photos/members/#{photo.id}"

  defp size(bytes) do
    image = Image.from_binary!(bytes)
    {Image.width(image), Image.height(image)}
  end

  test "shows the photo where the member placed it, with the tools and what to compare", %{
    conn: conn,
    team: team,
    cam: cam,
    photo: photo
  } do
    {:ok, lv, _html} = live(conn, check_path(team, photo))

    assert has_element?(lv, "#side-nav-photos[aria-current=page]")
    assert has_element?(lv, ~s|.breadcrumbs a[href="#{~p"/teams/#{team}/photos"}"]|, "Photos")
    assert has_element?(lv, "h1", "Photo from Cameron Ruiz")
    assert page_title(lv) =~ "Photo from Cameron Ruiz"

    # The square, starting where the member placed it, over the photo as taken.
    file = ~p"/teams/#{team}/photos/members/#{photo.id}/file"
    assert has_element?(lv, ~s|#accept-form .photo-place img[src^="#{file}?shape=taken"]|)
    assert has_element?(lv, "#accept-form .photo-place-oval")
    for tool <- ~w(rotate zoom-out zoom-in), do: assert(has_element?(lv, "#photo-#{tool}"))
    assert has_element?(lv, ~s|#accept-form input[name="photo[turns]"][value="1"]|)
    assert has_element?(lv, ~s|#accept-form input[name="photo[x]"][value="0.5"]|)
    assert has_element?(lv, ~s|#accept-form input[name="photo[y]"][value="0.4"]|)
    assert has_element?(lv, ~s|#accept-form input[name="photo[side]"][value="0.5"]|)

    member = ~p"/teams/#{team}/members/#{cam.id}"
    assert has_element?(lv, ~s|#photo-details a[href="#{member}"]|, "Cameron Ruiz")
    assert has_element?(lv, "#photo-details", "Added")
    assert has_element?(lv, "#photo-details", "Nov 12, 2026")
    assert has_element?(lv, ~s|#photo-as-taken[src^="#{file}?shape=taken"]|)
    assert has_element?(lv, "#photo-compare", "As taken")
    image = ~p"/teams/#{team}/members/#{cam.id}/image"
    assert has_element?(lv, ~s|#photo-on-card[src="#{image}"]|)
    assert has_element?(lv, "#photo-compare", "On the card now")

    assert has_element?(
             lv,
             "#photo-accept",
             "It becomes Cameron's photo. Phones that hold their ID card get it within a minute."
           )

    assert has_element?(lv, "#photo-accept-button[form=accept-form]", "Accept photo")

    assert has_element?(
             lv,
             "#photo-decline",
             "Cameron sees this beside the examples, and adds another."
           )

    assert lv
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.find("#decline-form label.choice")
           |> Enum.map(&(&1 |> Floki.text() |> String.trim())) ==
             [
               "Sunglasses",
               "Hat or helmet",
               "Too dark",
               "Someone else in it",
               "Busy background",
               "Not a photo of you",
               "Something else"
             ]

    assert has_element?(lv, "#decline-form label", "A message (optional)")
    assert has_element?(lv, "#photo-decline-button", "Decline photo")
  end

  test "a member with no photo yet has nothing on the card to compare", %{
    conn: conn,
    team: team,
    cam: cam,
    photo: photo
  } do
    cam |> Ecto.Changeset.change(has_photo: false) |> Repo.update!()

    {:ok, lv, _html} = live(conn, check_path(team, photo))

    assert has_element?(lv, "#photo-as-taken")
    refute has_element?(lv, "#photo-on-card")
  end

  test "Accept photo sends the square as placed now, deletes the file, and refreshes the card",
       %{conn: conn, team: team, cam: cam, photo: photo, user: user} do
    stub_ok()
    card = member_card_fixture(cam)
    {:ok, lv, _html} = live(conn, check_path(team, photo))

    # The team admin moved it: the middle of the photo, unturned, half its shorter side.
    {:ok, list, html} =
      lv
      |> form("#accept-form")
      |> render_submit(%{
        "photo" => %{"turns" => "0", "x" => "0.5", "y" => "0.5", "side" => "0.5"}
      })
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=waiting")

    assert html =~ "Photo accepted."
    assert has_element?(list, "#no-photos-waiting")

    assert_received {:records, "POST", "/documents", {:multipart, body}}
    assert body =~ ~s|name="profile"\r\n\r\ntrue|
    assert body =~ ~s|name="targetResourceId"\r\n\r\n#{cam.d4h_member_id}|

    [_headers, sent] =
      body |> String.split(~s|filename="photo.jpg"|) |> List.last() |> split_part()

    # 800 × 600 as taken: half the shorter side is a 300 px square.
    assert size(sent) == {300, 300}

    accepted = Repo.reload!(photo)
    assert accepted.status == :accepted
    assert accepted.decided_by_user_id == user.id
    assert %DateTime{} = accepted.decided_at
    assert {accepted.turns, accepted.side} == {0, 0.5}
    assert MemberPhotoFile.bytes(photo) == nil

    # It is the member's photo, as a team admin's own Add a photo makes it.
    cam = Repo.reload!(cam)
    assert %DateTime{} = cam.photo_changed_at
    assert [%ChangeSetRow{action: :set_member_photo, status: :applied}] = Repo.all(ChangeSetRow)
    # The card goes to the phones that hold it again.
    assert card.pass_updated_at == nil
    assert %DateTime{} = Repo.reload!(card).pass_updated_at
  end

  # The multipart part after the file's headers: its bytes, up to the next boundary.
  defp split_part(rest) do
    [headers, tail] = String.split(rest, "\r\n\r\n", parts: 2)
    [bytes | _after] = String.split(tail, "\r\n--", parts: 2)
    [headers, bytes]
  end

  test "a refused send leaves it waiting, and says who refused", %{
    conn: conn,
    team: team,
    cam: cam,
    photo: photo
  } do
    RecordsStub.stub(fn _method, _path, _body -> {403, %{"title" => "Forbidden"}} end)
    {:ok, lv, _html} = live(conn, check_path(team, photo))

    html = lv |> form("#accept-form") |> render_submit()

    assert html =~ D4H.error_text(team, %D4H.Error{status: 403, message: "Forbidden (403)"})
    assert has_element?(lv, "#accept-form .photo-place")
    assert %{status: :waiting, decided_at: nil} = Repo.reload!(photo)
    assert is_binary(MemberPhotoFile.bytes(photo))
    refute Repo.reload!(cam).photo_changed_at
  end

  test "Decline photo needs a reason", %{conn: conn, team: team, photo: photo} do
    {:ok, lv, _html} = live(conn, check_path(team, photo))

    html =
      lv
      |> form("#decline-form", decline: %{decline_message: "No reason picked"})
      |> render_submit()

    assert html =~ "Select why not."
    assert %{status: :waiting} = Repo.reload!(photo)
    assert is_binary(MemberPhotoFile.bytes(photo))
  end

  test "Decline photo keeps the reason and the message, and deletes the file", %{
    conn: conn,
    team: team,
    photo: photo,
    user: user
  } do
    {:ok, lv, _html} = live(conn, check_path(team, photo))

    {:ok, _list, html} =
      lv
      |> form("#decline-form",
        decline: %{decline_reason: "dark", decline_message: " Try by the hall's white wall. "}
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=waiting")

    assert html =~ "Photo declined."

    declined = Repo.reload!(photo)
    assert declined.status == :declined
    assert declined.decline_reason == :dark
    assert declined.decline_message == "Try by the hall's white wall."
    assert declined.decided_by_user_id == user.id
    assert MemberPhotoFile.bytes(photo) == nil
    # Nothing reached the team's records.
    refute_received {:records, _method, _path, _body}

    # The row stays, and its page says who decided, when, and why.
    {:ok, lv, _html} = live(conn, check_path(team, photo))
    assert has_element?(lv, "#photo-status", "Declined")
    assert has_element?(lv, "#photo-status", user.email)
    assert has_element?(lv, "#photo-decline-reason", "Too dark")
    assert has_element?(lv, "#photo-decline-reason", "Try by the hall's white wall.")
    assert has_element?(lv, "#photo-file-gone", "when it was declined")
    refute has_element?(lv, "#accept-form")
    refute has_element?(lv, "#decline-form")
  end

  test "a message over 300 characters is refused", %{conn: conn, team: team, photo: photo} do
    {:ok, lv, _html} = live(conn, check_path(team, photo))

    html =
      render_submit(lv, "decline", %{
        "decline" => %{
          "decline_reason" => "dark",
          "decline_message" => String.duplicate("a", 301)
        }
      })

    assert html =~ "Keep it under 300 characters."
    assert %{status: :waiting} = Repo.reload!(photo)
  end

  test "a photo the member replaced since the page opened is no longer there to decide", %{
    conn: conn,
    team: team,
    cam: cam,
    photo: photo
  } do
    {:ok, lv, _html} = live(conn, check_path(team, photo))
    {:ok, taken} = 400 |> png_fixture(400) |> Service.MemberPhoto.prepare()
    {:ok, newer} = AddOwnPhoto.call(cam, taken, {0, %{x: 0.5, y: 0.5, side: 1.0}})

    {:ok, _list, html} =
      lv
      |> form("#accept-form")
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=waiting")

    assert html =~ "This photo is no longer waiting."
    refute_received {:records, _method, _path, _body}
    assert %MemberPhoto{status: :waiting} = Repo.reload!(newer)
  end

  test "another team's photo is not found, nor any with the switch off", %{
    conn: conn,
    team: team,
    photo: photo
  } do
    other = member_photo_fixture(member_fixture(team_fixture(%{photos_enabled: true})))

    assert_raise Ecto.NoResultsError, fn -> live(conn, check_path(team, other)) end

    assert_error_sent 404, fn ->
      get(conn, ~p"/teams/#{team}/photos/members/#{other.id}/file")
    end

    team |> Ecto.Changeset.change(photos_enabled: false) |> Repo.update!()
    assert_raise Web.Status.NotFound, fn -> live(conn, check_path(team, photo)) end
  end

  describe "the waiting photo's file" do
    test "is the photo as taken, or the square the member placed", %{
      conn: conn,
      team: team,
      photo: photo
    } do
      taken = get(conn, ~p"/teams/#{team}/photos/members/#{photo.id}/file?shape=taken")
      assert get_resp_header(taken, "content-type") == ["image/jpeg"]
      assert get_resp_header(taken, "cache-control") == ["private, no-store"]
      assert taken |> response(200) |> size() == {800, 600}

      # Turned once and half the shorter side: a 300 px square.
      placed = get(conn, ~p"/teams/#{team}/photos/members/#{photo.id}/file?shape=placed")
      assert placed |> response(200) |> size() == {300, 300}
    end

    test "is gone once the photo is decided", %{conn: conn, team: team, photo: photo, user: user} do
      {:ok, _declined} =
        DeclineMemberPhoto.call(team, photo, "dark", nil, user, DateTime.utc_now())

      assert conn |> get(~p"/teams/#{team}/photos/members/#{photo.id}/file") |> response(404)
    end

    test "has no cleaned-up copy without Clean up", %{conn: conn, team: team, photo: photo} do
      path = ~p"/teams/#{team}/photos/members/#{photo.id}/file?shape=cleaned"
      assert conn |> get(path) |> response(404)
    end
  end

  # Clean up (#1031): a photo that kept a cleaned-up copy gets the member's switch.
  describe "with Clean up" do
    alias App.CleanUpStandIn

    # Cameron's photo with a 500 × 500 cleaned-up copy, placed with the switch `on?`.
    defp cleaned_photo(cam, on?) do
      member_photo_fixture(cam, %{
        clean_up: on?,
        cleaned_width: 500,
        cleaned_height: 500,
        x: 0.4,
        y: 0.6,
        side: 0.8
      })
    end

    defp sent_size do
      assert_received {:records, "POST", "/documents", {:multipart, body}}

      [_headers, sent] =
        body |> String.split(~s|filename="photo.jpg"|) |> List.last() |> split_part()

      size(sent)
    end

    test "off: no switch on any photo, and Busy background is a reason", %{
      conn: conn,
      team: team,
      cam: cam,
      photo: photo
    } do
      {:ok, lv, _html} = live(conn, check_path(team, photo))
      refute has_element?(lv, "#photo-clean-up")
      assert has_element?(lv, "#decline-form label.choice", "Busy background")

      # One added while Clean up ran still shows what the member placed, with no switch.
      kept = cleaned_photo(cam, true)
      {:ok, lv, _html} = live(conn, check_path(team, kept))
      refute has_element?(lv, "#photo-clean-up")
      file = ~p"/teams/#{team}/photos/members/#{kept.id}/file"
      assert has_element?(lv, ~s|#accept-form .photo-place img[src^="#{file}?shape=cleaned"]|)
    end

    test "the switch starts where the member left it, over the photo they placed", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      CleanUpStandIn.turn_on()
      photo = cleaned_photo(cam, true)
      file = ~p"/teams/#{team}/photos/members/#{photo.id}/file"
      {:ok, lv, _html} = live(conn, check_path(team, photo))

      assert has_element?(lv, "#accept-form #photo-clean-up[role=switch][checked]")
      assert has_element?(lv, "label[for=photo-clean-up]", "Clean up")

      assert has_element?(
               lv,
               "#photo-clean-up-hint",
               "Removes the background and centres the face. Turn it off to use the photo as Cameron took it."
             )

      cleaned = ~s|#accept-form .photo-place img[src^="#{file}?shape=cleaned"]|
      assert has_element?(lv, cleaned <> ~s|[width="500"][height="500"]|)
      assert has_element?(lv, ~s|#accept-form input[name="photo[x]"][value="0.4"]|)
      assert has_element?(lv, ~s|#accept-form input[name="photo[side]"][value="0.8"]|)
      # Compare still shows the photo as taken.
      assert has_element?(lv, ~s|#photo-as-taken[src^="#{file}?shape=taken"]|)

      # Off shows the photo as taken, which nobody has placed: the middle square.
      lv |> element("#photo-clean-up") |> render_click()

      refute has_element?(lv, "#photo-clean-up[checked]")
      taken = ~s|#accept-form .photo-place img[src^="#{file}?shape=taken"]|
      assert has_element?(lv, taken <> ~s|[width="800"][height="600"]|)
      assert has_element?(lv, ~s|#accept-form input[name="photo[x]"][value="0.5"]|)
      assert has_element?(lv, ~s|#accept-form input[name="photo[side]"][value="1.0"]|)

      # On again is where the member placed it.
      lv |> element("#photo-clean-up") |> render_click()
      assert has_element?(lv, cleaned)
      assert has_element?(lv, ~s|#accept-form input[name="photo[side]"][value="0.8"]|)
    end

    test "a member who turned it off starts off, where they placed the photo as taken", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      CleanUpStandIn.turn_on()
      photo = cleaned_photo(cam, false)
      file = ~p"/teams/#{team}/photos/members/#{photo.id}/file"
      {:ok, lv, _html} = live(conn, check_path(team, photo))

      assert has_element?(lv, "#photo-clean-up[role=switch]")
      refute has_element?(lv, "#photo-clean-up[checked]")
      assert has_element?(lv, ~s|#accept-form .photo-place img[src^="#{file}?shape=taken"]|)
      assert has_element?(lv, ~s|#accept-form input[name="photo[side]"][value="0.8"]|)

      lv |> element("#photo-clean-up") |> render_click()
      assert has_element?(lv, ~s|#accept-form .photo-place img[src^="#{file}?shape=cleaned"]|)
      assert has_element?(lv, ~s|#accept-form input[name="photo[side]"][value="1.0"]|)
    end

    test "a photo with no cleaned-up copy has no switch, and Busy background is not a reason",
         %{conn: conn, team: team, photo: photo} do
      CleanUpStandIn.turn_on()
      {:ok, lv, _html} = live(conn, check_path(team, photo))

      refute has_element?(lv, "#photo-clean-up")
      refute has_element?(lv, "#decline-form label.choice", "Busy background")
      assert has_element?(lv, "#decline-form label.choice", "Too dark")
    end

    test "Accept photo sends the cleaned-up photo with the switch on", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      CleanUpStandIn.turn_on()
      stub_ok()
      photo = cleaned_photo(cam, true)
      {:ok, lv, _html} = live(conn, check_path(team, photo))

      lv
      |> form("#accept-form")
      |> render_submit(%{"photo" => %{"x" => "0.5", "y" => "0.5", "side" => "1.0"}})
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=waiting")

      # The whole of the 500 × 500 cleaned-up photo.
      assert sent_size() == {500, 500}
      assert %{status: :accepted, clean_up: true} = Repo.reload!(photo)
      assert MemberPhotoFile.bytes(photo, :taken) == nil
      assert MemberPhotoFile.bytes(photo, :cleaned) == nil
    end

    test "Accept photo sends the photo as taken with the switch turned off", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      CleanUpStandIn.turn_on()
      stub_ok()
      photo = cleaned_photo(cam, true)
      {:ok, lv, _html} = live(conn, check_path(team, photo))
      lv |> element("#photo-clean-up") |> render_click()

      lv
      |> form("#accept-form")
      |> render_submit(%{"photo" => %{"x" => "0.5", "y" => "0.5", "side" => "1.0"}})
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=waiting")

      # The middle square of the 800 × 600 photo as taken.
      assert sent_size() == {600, 600}
      assert %{status: :accepted, clean_up: false} = Repo.reload!(photo)
    end

    test "Accept photo sends the cleaned-up photo when the team admin turns the switch on", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      CleanUpStandIn.turn_on()
      stub_ok()
      photo = cleaned_photo(cam, false)
      {:ok, lv, _html} = live(conn, check_path(team, photo))
      lv |> element("#photo-clean-up") |> render_click()

      lv
      |> form("#accept-form")
      |> render_submit(%{"photo" => %{"x" => "0.5", "y" => "0.5", "side" => "1.0"}})
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=waiting")

      assert sent_size() == {500, 500}
      assert %{status: :accepted, clean_up: true} = Repo.reload!(photo)
    end
  end
end
