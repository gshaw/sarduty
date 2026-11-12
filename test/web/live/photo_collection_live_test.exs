defmodule Web.PhotoCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  # Photos (#1028): every current member's photo, for team admins, behind the switch.
  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{photos_enabled: true}})
    %{conn: log_in_user(conn, user), user: user, team: team}
  end

  test "the counts filter a grid of every current member, A to Z", %{conn: conn, team: team} do
    sam = member_fixture(team, %{name: "Sam Rivera"})
    eli = member_fixture(team, %{name: "Eli Haddad", has_photo: false})
    alex = member_fixture(team, %{name: "alex Chen"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos")

    assert has_element?(lv, "#side-nav-photos[aria-current=page]")
    assert has_element?(lv, "#photos-view-members[aria-current=page]", "4")
    assert has_element?(lv, "#photos-view-no-photo", "1")

    # The team admin from the setup is on the team too.
    assert lv |> render() |> Floki.parse_fragment!() |> Floki.find("#photos > li") |> length() ==
             4

    assert render(lv) =~ ~r/alex Chen.*Eli Haddad.*Sam Rivera/s

    # A photo comes from the member's image route, loaded as it scrolls into view.
    image = ~p"/teams/#{team}/members/#{sam.id}/image"
    assert has_element?(lv, ~s|#photo-#{sam.id} img[src="#{image}"][loading=lazy]|)
    refute has_element?(lv, "#photo-#{sam.id}-add")
    assert has_element?(lv, "#photo-#{alex.id} img")

    # No photo: initials in a dashed tile, and a link to add one.
    assert has_element?(lv, "#photo-#{eli.id} .photo-tile-none", "EH")
    refute has_element?(lv, "#photo-#{eli.id} img")
    add = ~p"/teams/#{team}/photos/members/new?#{[member: eli.id]}"
    assert has_element?(lv, ~s|#photo-#{eli.id}-add[href="#{add}"]|, "Add a photo")

    # The name opens the member's ID Card tab.
    card = ~p"/teams/#{team}/members/#{eli.id}/card"
    assert has_element?(lv, ~s|#photo-#{eli.id}-name[href="#{card}"]|, "Eli Haddad")
    assert has_element?(lv, ~s|#photo-add[href="#{~p"/teams/#{team}/photos/members/new"}"]|)

    lv |> element("#photos-view-no-photo") |> render_click()
    assert_patch(lv, ~p"/teams/#{team}/photos?view=no-photo")
    assert has_element?(lv, "#photos-view-no-photo[aria-current=page]")
    assert has_element?(lv, "#photo-#{eli.id}")
    refute has_element?(lv, "#photo-#{sam.id}")
  end

  test "a photo SAR Duty changed carries its time, so the browser loads the new one",
       %{conn: conn, team: team} do
    sam = member_fixture(team, %{name: "Sam Rivera"})
    sam |> Ecto.Changeset.change(photo_changed_at: ~U[2026-11-12 08:00:00Z]) |> Repo.update!()

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos")

    image = ~p"/teams/#{team}/members/#{sam.id}/image?v=1794470400"
    assert has_element?(lv, ~s|#photo-#{sam.id} img[src="#{image}"]|)
  end

  test "retiring, retired, and not-a-person members are not in the grid", %{
    conn: conn,
    team: team
  } do
    leavers = group_fixture(team, %{title: "Leavers"})
    team |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id) |> Repo.update!()
    retiring = member_fixture(team, %{name: "Avery Retiring"})
    group_member_fixture(leavers, retiring)
    retired = member_fixture(team, %{name: "Old Timer", left_at: ~U[2020-01-01 00:00:00Z]})
    truck = member_fixture(team, %{name: "Truck 1", not_a_person: true, has_photo: false})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos")

    for member <- [retiring, retired, truck], do: refute(has_element?(lv, "#photo-#{member.id}"))
    assert has_element?(lv, "#photos-view-members", "1")
    assert has_element?(lv, "#photos-view-no-photo", "0")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos?view=no-photo")
    assert has_element?(lv, "#no-photos", "Every current member has a photo")
  end

  test "with the switch off the pages are not found, and there is no link", %{
    conn: conn,
    team: team
  } do
    team |> Ecto.Changeset.change(photos_enabled: false) |> Repo.update!()

    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/photos") end

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/photos/members/new")
    end

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
    refute has_element?(lv, "#side-nav-photos")
  end

  test "a view that is not one is not found", %{conn: conn, team: team} do
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/photos?view=asked") end
  end

  # Photos members added of themselves (#1029), for a team admin to check.
  describe "photos waiting" do
    test "Waiting counts them and lists them oldest first, each opening its check", %{
      conn: conn,
      team: team
    } do
      sam = member_fixture(team, %{name: "Sam Rivera"})
      eli = member_fixture(team, %{name: "Eli Haddad", has_photo: false})
      newer = member_photo_fixture(sam, %{inserted_at: ~U[2026-11-12 20:00:00.000000Z]})
      older = member_photo_fixture(eli, %{inserted_at: ~U[2026-11-10 20:00:00.000000Z]})
      # One a team admin decided does not wait.
      member_photo_fixture(sam, %{status: :declined, decline_reason: :dark})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos")

      assert has_element?(lv, "#photos-view-waiting", "2")
      # In the grid, the member's badge opens the check, in Add a photo's place.
      check = ~p"/teams/#{team}/photos/members/#{older.id}"
      assert has_element?(lv, ~s|#photo-#{eli.id}-waiting[href="#{check}"]|, "New photo waiting")
      refute has_element?(lv, "#photo-#{eli.id}-add")
      assert has_element?(lv, "#photo-#{sam.id}-waiting", "New photo waiting")

      lv |> element("#photos-view-waiting") |> render_click()
      assert_patch(lv, ~p"/teams/#{team}/photos?view=waiting")

      assert lv
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.find("#photos-waiting > li")
             |> Enum.flat_map(&Floki.attribute(&1, "id")) ==
               ["waiting-#{older.id}", "waiting-#{newer.id}"]

      assert has_element?(lv, ~s|#waiting-#{older.id}-name[href="#{check}"]|, "Eli Haddad")
      assert has_element?(lv, "#waiting-#{older.id}", "Added Nov 10, 2026")
      # The square the member placed, from the photo SAR Duty keeps.
      file = ~p"/teams/#{team}/photos/members/#{older.id}/file"
      assert has_element?(lv, ~s|#waiting-#{older.id}-photo img[src^="#{file}?shape=placed"]|)
    end

    test "with none waiting, the view says so", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos?view=waiting")

      assert has_element?(lv, "#photos-view-waiting[aria-current=page]", "0")
      assert has_element?(lv, "#no-photos-waiting", "No photos waiting")
    end

    test "a retiring member's waiting photo does not count", %{conn: conn, team: team} do
      leavers = group_fixture(team, %{title: "Leavers"})
      team |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id) |> Repo.update!()
      retiring = member_fixture(team, %{name: "Avery Retiring"})
      group_member_fixture(leavers, retiring)
      photo = member_photo_fixture(retiring)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos?view=waiting")

      assert has_element?(lv, "#photos-view-waiting", "0")
      refute has_element?(lv, "#waiting-#{photo.id}")
    end

    # An activity's photos wait here too (#1032): after the members', by activity, each
    # opening the activity's Photos tab, where a team admin accepts or deletes them.
    test "lists members' photos, then each activity's, and counts both", %{conn: conn, team: team} do
      eli = member_fixture(team, %{name: "Eli Haddad"})
      own = member_photo_fixture(eli)

      swiftwater =
        activity_fixture(team, %{
          title: "Swiftwater training",
          started_at: ~U[2026-11-04 03:00:00Z]
        })

      rope = activity_fixture(team, %{title: "Rope rescue", started_at: ~U[2026-11-10 03:00:00Z]})
      first = activity_photo_fixture(swiftwater, %{member_id: eli.id})
      second = activity_photo_fixture(swiftwater, %{member_id: eli.id})
      third = activity_photo_fixture(rope, %{member_id: eli.id, caption: "On the wall."})
      accepted = activity_photo_fixture(rope, %{status: :accepted})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos?view=waiting")

      # 1 member photo and 3 on activities. An accepted photo waits for nobody.
      assert has_element?(lv, "#photos-view-waiting[aria-current=page]", "4")
      assert has_element?(lv, "#photos-waiting-members", "Member photos")
      assert has_element?(lv, "#waiting-#{own.id}")

      # The later activity first, each under its title.
      assert lv
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.find("section[id^=photos-waiting-activity-]")
             |> Floki.attribute("id") ==
               ["photos-waiting-activity-#{rope.id}", "photos-waiting-activity-#{swiftwater.id}"]

      tab = ~p"/teams/#{team}/activities/#{swiftwater.id}/photos"

      assert has_element?(
               lv,
               ~s|#photos-waiting-activity-#{swiftwater.id}-link[href="#{tab}"]|,
               "Swiftwater training"
             )

      assert has_element?(
               lv,
               "#photos-waiting-activity-#{swiftwater.id}",
               "Nov 3, 2026 · 2 photos waiting"
             )

      assert has_element?(lv, "#photos-waiting-activity-#{rope.id}", "1 photo waiting")

      for photo <- [first, second] do
        assert has_element?(
                 lv,
                 ~s|#photos-waiting-activity-#{swiftwater.id} #activity-photo-#{photo.id} img[src*="/photos/#{photo.id}/file?size=tile"]|
               )
      end

      assert has_element?(lv, "#activity-photo-#{first.id}", "Eli Haddad")
      assert has_element?(lv, ~s|#activity-photo-#{third.id} img[alt="On the wall."]|)
      refute has_element?(lv, "#activity-photo-#{accepted.id}")
    end

    test "an activity's photos alone need no heading over the members'", %{conn: conn, team: team} do
      photo = activity_photo_fixture(activity_fixture(team))

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos?view=waiting")

      assert has_element?(lv, "#photos-view-waiting", "1")
      assert has_element?(lv, "#activity-photo-#{photo.id}")
      refute has_element?(lv, "#photos-waiting-members")
      refute has_element?(lv, "#no-photos-waiting")
    end
  end

  # A member's own part (#1029): their photo and where it stands, and nothing of the
  # team's.
  describe "as a member" do
    setup %{conn: conn} do
      %{team: team, member: cam, user: user} =
        member_with_login_fixture(%{name: "Cameron Ruiz", has_photo: false})

      team = team |> Ecto.Changeset.change(photos_enabled: true) |> Repo.update!()
      %{conn: log_in_user(conn, user), team: team, cam: cam}
    end

    test "Photos is in the side navigation, and shows only their own photo", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      other = member_fixture(team, %{name: "Sam Rivera"})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos")

      assert has_element?(lv, "#side-nav-photos[aria-current=page]", "Photos")
      assert has_element?(lv, "#your-photo h2", "Your photo")
      assert has_element?(lv, "#your-photo-none", "You have no photo yet.")
      add = ~p"/teams/#{team}/photos/members/new"
      assert has_element?(lv, ~s|#your-photo-add[href="#{add}"]|, "Add a photo")

      # None of the views of members' photos: no grid, no other member.
      for view <- ~w(members no-photo waiting),
          do: refute(has_element?(lv, "#photos-view-#{view}"))

      refute has_element?(lv, "#photo-ask")
      refute has_element?(lv, "#photo-add")
      refute has_element?(lv, "#photos")
      refute has_element?(lv, "#photo-#{other.id}")
      refute has_element?(lv, "#photo-#{cam.id}")
      refute has_element?(lv, "#photo-on-card")
    end

    test "with a photo, they see it and Change photo", %{conn: conn, team: team, cam: cam} do
      cam |> Ecto.Changeset.change(has_photo: true) |> Repo.update!()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos")

      image = ~p"/teams/#{team}/members/#{cam.id}/image"
      assert has_element?(lv, ~s|#your-photo-now[src="#{image}"]|)
      assert has_element?(lv, "#your-photo-add", "Change photo")
      refute has_element?(lv, "#your-photo-none")
      refute has_element?(lv, "#your-photo-status")
    end

    test "while one waits, it shows as Waiting over the photo their ID card still has", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      cam |> Ecto.Changeset.change(has_photo: true) |> Repo.update!()
      photo = member_photo_fixture(cam, %{inserted_at: ~U[2026-11-12 20:00:00.000000Z]})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos")

      file = ~p"/teams/#{team}/photos/members/#{photo.id}/file"
      assert has_element?(lv, ~s|#your-photo-waiting[src^="#{file}?shape=placed"]|)
      assert has_element?(lv, "#your-photo-status .badge", "Waiting")

      assert has_element?(
               lv,
               "#your-photo-status",
               "Added Nov 12, 2026. A team admin checks it before your ID card shows it."
             )

      assert has_element?(lv, "#your-photo-add", "Change photo")
      assert has_element?(lv, "#photo-on-card h2", "On your ID card now")
      image = ~p"/teams/#{team}/members/#{cam.id}/image"
      assert has_element?(lv, ~s|#photo-on-card-image[src="#{image}"]|)
    end

    test "a declined one says when and why, until they add another", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      member_photo_fixture(cam, %{
        status: :declined,
        decline_reason: :dark,
        decided_at: ~U[2026-11-12 21:00:00.000000Z]
      })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos")

      assert has_element?(lv, "#your-photo-declined", "Declined Nov 12, 2026: Too dark.")
      assert has_element?(lv, "#your-photo-none")
      assert has_element?(lv, "#your-photo-add", "Add a photo")

      member_photo_fixture(cam)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos")
      refute has_element?(lv, "#your-photo-declined")
      assert has_element?(lv, "#your-photo-status .badge", "Waiting")
    end

    test "the team's views, the check page, and another member's photo are not found", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      other = member_fixture(team, %{name: "Sam Rivera"})
      theirs = member_photo_fixture(other)
      own = member_photo_fixture(cam)

      for view <- ~w(waiting no-photo members) do
        assert_raise Web.Status.NotFound, fn ->
          live(conn, ~p"/teams/#{team}/photos?#{[view: view]}")
        end
      end

      for photo <- [theirs, own] do
        assert_raise Web.Status.NotFound, fn ->
          live(conn, ~p"/teams/#{team}/photos/members/#{photo.id}")
        end
      end

      # Their own waiting photo's file opens; another member's does not.
      assert conn |> get(~p"/teams/#{team}/photos/members/#{own.id}/file") |> response(200)

      assert_error_sent 404, fn ->
        get(conn, ~p"/teams/#{team}/photos/members/#{theirs.id}/file")
      end
    end

    test "with the switch off there is no page and no link", %{conn: conn, team: team} do
      team |> Ecto.Changeset.change(photos_enabled: false) |> Repo.update!()

      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/photos") end

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      refute has_element?(lv, "#side-nav-photos")
    end
  end

  test "a team admin who is also a member sees the team's views", %{conn: conn} do
    %{team: team, user: user} = member_with_login_fixture(%{name: "Alex Chen", d4h_permission: 0})
    team |> Ecto.Changeset.change(photos_enabled: true) |> Repo.update!()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/photos")

    assert has_element?(lv, "#photos-switch")
    assert has_element?(lv, "#photos")
    refute has_element?(lv, "#your-photo")
  end
end
