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
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/photos?view=waiting") end
  end

  # Team admins' in this part: members get the page when they add their own (#1029).
  test "a member who is not a team admin does not open it", %{conn: conn} do
    %{team: team, user: user} = member_with_login_fixture()
    team |> Ecto.Changeset.change(photos_enabled: true) |> Repo.update!()
    conn = log_in_user(conn, user)

    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/photos") end

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
    refute has_element?(lv, "#side-nav-photos")
  end
end
