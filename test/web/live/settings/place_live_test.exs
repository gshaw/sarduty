defmodule Web.Settings.PlaceLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.D4H
  alias App.Model.LocationBookmark
  alias App.RecordsStub
  alias App.Repo

  defp bookmark_json(id, title),
    do: %{
      "id" => id,
      "title" => title,
      "address" => %{"street" => "12 Main St"},
      "location" => %{"type" => "Point", "coordinates" => [-122.8, 49.1]},
      "archivedAt" => nil
    }

  describe "a SAR Duty Records team" do
    setup %{conn: conn} do
      %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
      %{conn: log_in_user(conn, user), team: team}
    end

    test "a team admin adds a place from one the team's activities used",
         %{conn: conn, team: team} do
      for _ <- 1..2,
          do: activity_fixture(team, %{address: "Hall, Surrey", coordinate: "49.1,-122.8"})

      hall = bookmark_json(41, "Hall")
      RecordsStub.stub(fn _method, _path, _body -> {200, hall} end)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/places")
      assert has_element?(lv, ".tabs a", "Places")
      assert has_element?(lv, "#no-places")
      {:ok, lv, _html} = lv |> element("#place-add") |> render_click() |> follow_redirect(conn)

      html = lv |> form("#place-form", place: %{title: " "}) |> render_submit()
      assert html =~ "Enter a name."
      refute_received {:records, _, _, _}

      # The same address box as an activity's.
      lv |> element("#place_place") |> render_focus()
      assert has_element?(lv, "#place-past-0", "Hall, Surrey")
      assert has_element?(lv, "#place-past-0", "2 activities")
      lv |> element("#place-past-0") |> render_click()
      assert has_element?(lv, "#place-pin", "49.10000, -122.80000")

      {:ok, _lv, html} =
        lv
        |> form("#place-form", place: %{title: " Hall "})
        |> render_submit()
        |> follow_redirect(conn, ~p"/teams/#{team}/settings/places")

      assert html =~ "Saved Hall."
      assert_received {:records, "POST", "/location-bookmarks", body}

      assert body == %{
               "title" => "Hall",
               "address" => %{
                 "street" => "Hall, Surrey",
                 "town" => "",
                 "region" => "",
                 "country" => ""
               },
               "location" => %{"latitude" => 49.1, "longitude" => -122.8}
             }
    end

    test "a pasted latitude and longitude is the pin", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/places/new")

      lv
      |> form("#place-form", place: %{place: "49°06'N 122°48'W"})
      |> render_change(%{"_target" => ["place", "place"]})

      assert has_element?(lv, "#place-pin", "49.10000, -122.80000")
    end

    test "a team admin moves a place, then deletes it", %{conn: conn, team: team} do
      place = location_bookmark_fixture(team, %{title: "!Hall", d4h_location_bookmark_id: 41})

      hall = bookmark_json(41, "!Hall")
      RecordsStub.stub(fn _method, _path, _body -> {200, hall} end)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/places")
      assert has_element?(lv, "#place-#{place.id}", "Hall")
      refute has_element?(lv, "#place-#{place.id}", "!")
      assert has_element?(lv, "#place-#{place.id}", "49.03879, -122.73734")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/places/#{place.id}")

      lv |> element("#place-pin-remove") |> render_click()
      refute has_element?(lv, "#place-pin")
      lv |> form("#place-form") |> render_submit()

      assert_received {:records, "PATCH", "/location-bookmarks/41", body}
      assert body["title"] == "!Hall"
      assert body["location"] == nil

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/places/#{place.id}")

      {:ok, _lv, html} =
        lv
        |> element("#place-delete")
        |> render_click()
        |> follow_redirect(conn, ~p"/teams/#{team}/settings/places")

      assert html =~ "Deleted Hall."
      assert_received {:records, "DELETE", "/location-bookmarks/41", nil}
      refute Repo.get(LocationBookmark, place.id)
    end

    test "another team's place is not found", %{conn: conn, team: team} do
      other =
        location_bookmark_fixture(team_fixture(%{d4h_api_host: D4H.records_host()}))

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/teams/#{team}/settings/places/#{other.id}")
      end
    end
  end

  describe "a D4H team" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "d4h_key"}})
      %{conn: log_in_user(conn, user), team: team}
    end

    test "lists its bookmarks to change in D4H, with no form", %{conn: conn, team: team} do
      place = location_bookmark_fixture(team, %{title: "Office", coordinate: nil})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/places")
      assert has_element?(lv, "#places-in-service", "Location Bookmarks")
      assert has_element?(lv, "#place-#{place.id}", "Office")
      assert has_element?(lv, "#place-#{place.id}", "None")
      refute has_element?(lv, "#place-add")
      refute has_element?(lv, "#place-#{place.id} a")

      assert_raise Web.Status.NotFound, fn ->
        live(conn, ~p"/teams/#{team}/settings/places/#{place.id}")
      end
    end
  end
end
