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

    test "a team admin adds a place with a pasted pin", %{conn: conn, team: team} do
      hall = bookmark_json(41, "Hall")
      RecordsStub.stub(fn _method, _path, _body -> {200, hall} end)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/places")
      assert has_element?(lv, ".tabs a", "Places")
      assert has_element?(lv, "#no-places")
      {:ok, lv, _html} = lv |> element("#place-add") |> render_click() |> follow_redirect(conn)

      html =
        lv
        |> form("#place-form", place: %{title: "Hall", place: "", pin: "nowhere"})
        |> render_submit()

      assert html =~ "Enter a latitude and longitude"
      refute_received {:records, _, _, _}

      {:ok, _lv, html} =
        lv
        |> form("#place-form",
          place: %{title: " Hall ", place: "12 Main St, Surrey", pin: "49°06'N 122°48'W"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/teams/#{team}/settings/places")

      assert html =~ "Saved Hall."

      assert_received {:records, "POST", "/location-bookmarks", body}

      assert body == %{
               "title" => "Hall",
               "address" => %{
                 "street" => "12 Main St, Surrey",
                 "town" => "",
                 "region" => "",
                 "country" => ""
               },
               "location" => %{"latitude" => 49.1, "longitude" => -122.8}
             }
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

      lv
      |> form("#place-form", place: %{pin: ""})
      |> render_submit()

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
