defmodule Web.ActivityFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.LocationBookmark
  alias App.RecordsStub
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
    %{conn: log_in_user(conn, user), team: team}
  end

  defp stub(reply \\ fn _method, _path, _body -> {200, RecordsStub.activity_json(88)} end),
    do: RecordsStub.stub(reply, %{"/tags" => RecordsStub.tags_json()})

  defp edit_rows(team) do
    ChangeSet
    |> Repo.all(team_id: team.id)
    |> Repo.preload(:rows)
    |> Enum.filter(&(&1.source == :edit))
    |> Enum.flat_map(& &1.rows)
  end

  test "a team admin adds an incident that counts for primary hours", %{conn: conn, team: team} do
    stub()
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/activities")
    assert has_element?(list, "#activity-add")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

    {:ok, _lv, html} =
      lv
      |> form("#activity-form",
        form: %{
          kind: "incident",
          title: "Missing hiker",
          starts_at: "2026-10-08T18:30",
          ends_at: "2026-10-08T23:00",
          place: "Murrin Park",
          hours: "primary"
        }
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Saved Missing hiker."

    assert_received {:records, "POST", "/incidents", body}
    assert body["referenceDescription"] == "Missing hiker"
    assert body["startsAt"] == "2026-10-09T01:30:00Z"

    assert body["address"] == %{
             "street" => "Murrin Park",
             "town" => "",
             "region" => "",
             "postcode" => "",
             "country" => ""
           }

    assert_received {:records, "POST", "/incidents/88/tags", %{"tagIds" => [1]}}
    assert_received {:records, "POST", "/incidents/88/publish", %{"published" => false}}
    assert [%ChangeSetRow{action: :create_activity, status: :applied}] = edit_rows(team)
  end

  # The activity exists in Records once the POST answers, so the save keeps its id rather
  # than failing and being tried again, which would make a second one.
  test "a new activity keeps its id when its tags fail", %{conn: conn, team: team} do
    stub(fn
      "POST", "/exercises", _body -> {200, RecordsStub.activity_json(88)}
      _method, _path, _body -> {400, %{"title" => "Unknown tag."}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

    lv
    |> form("#activity-form",
      form: %{title: "Practice", starts_at: "2026-10-08T18:00", ends_at: "2026-10-08T20:00"}
    )
    |> render_submit()

    assert [%ChangeSetRow{status: :applied, d4h_record_id: 88}] = edit_rows(team)
  end

  test "a change sends only what changed, and delete marks the activity deleted",
       %{conn: conn, team: team} do
    stub()
    activity = activity_fixture(team, %{title: "Practice", d4h_activity_id: 88})

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
    assert has_element?(page, "#activity-actions #activity-edit")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")

    lv
    |> form("#activity-form", form: %{title: "Rope practice", hours: "secondary"})
    |> render_submit()

    assert_received {:records, "PATCH", "/exercises/88",
                     %{"referenceDescription" => "Rope practice"} = body}

    assert map_size(body) == 1
    assert_received {:records, "POST", "/exercises/88/tags", %{"tagIds" => [2]}}

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")
    lv |> element("#activity-delete-button") |> render_click()

    assert_received {:records, "DELETE", "/exercises/88", nil}
    assert Repo.reload!(activity).deleted_at
  end

  test "a finish before the start is refused, in the summary too", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

    lv
    |> form("#activity-form",
      form: %{title: "Backwards", starts_at: "2026-10-08T18:00", ends_at: "2026-10-08T17:00"}
    )
    |> render_submit()

    assert has_element?(lv, "#activity-form .error-summary", "Enter a finish after the start.")
  end

  test "a deleted activity cannot be changed", %{conn: conn, team: team} do
    activity = activity_fixture(team, %{deleted_at: ~U[2026-10-01 00:00:00Z]})

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")
    end
  end

  describe "the place (#610)" do
    defp stub_mapbox do
      test = self()

      Req.Test.stub(App.Adapter.Mapbox, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        send(test, {:mapbox, conn.request_path, conn.query_params})

        case conn.request_path do
          "/search/searchbox/v1/suggest" ->
            Req.Test.json(conn, %{
              "suggestions" => [
                %{
                  "name" => "Campbell Valley Regional Park",
                  "mapbox_id" => "park-1",
                  "full_address" => "20285 8 Ave, Langley, V2Z 1V5, Canada"
                }
              ]
            })

          "/search/searchbox/v1/retrieve/park-1" ->
            Req.Test.json(conn, %{
              "type" => "FeatureCollection",
              "features" => [
                %{
                  "geometry" => %{"type" => "Point", "coordinates" => [-122.656341, 49.017322]},
                  "properties" => %{
                    "name" => "Campbell Valley Regional Park",
                    "full_address" => "20285 8 Ave, Langley, V2Z 1V5, Canada",
                    "context" => %{"country" => %{"name" => "Canada"}}
                  }
                }
              ]
            })
        end
      end)
    end

    defp type_place(lv, text) do
      lv
      |> form("#activity-form", form: %{place: text})
      |> render_change(%{"_target" => ["form", "place"]})
    end

    test "typing lists places, and the one picked is the address and the pin",
         %{conn: conn, team: team} do
      stub()
      stub_mapbox()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

      type_place(lv, "campbell valley")
      render_async(lv)

      assert_received {:mapbox, "/search/searchbox/v1/suggest", %{"q" => "campbell valley"} = q}
      assert q["session_token"]
      assert has_element?(lv, "#activity-place-0", "Campbell Valley Regional Park")

      lv |> element("#activity-place-0") |> render_click()

      assert_received {:mapbox, "/search/searchbox/v1/retrieve/park-1", retrieve}
      assert retrieve["session_token"] == q["session_token"]
      refute has_element?(lv, "#activity-places")
      assert has_element?(lv, "#activity-pin", "49.01732, -122.65634")

      lv
      |> form("#activity-form",
        form: %{
          title: "Night navigation",
          starts_at: "2026-10-08T18:30",
          ends_at: "2026-10-08T21:00"
        }
      )
      |> render_submit()

      assert_received {:records, "POST", "/exercises", body}

      assert body["address"]["street"] ==
               "Campbell Valley Regional Park, 20285 8 Ave, Langley, V2Z 1V5"

      assert body["location"] == %{"latitude" => 49.01732, "longitude" => -122.65634}
    end

    test "a pasted latitude and longitude is the pin, with no search",
         %{conn: conn, team: team} do
      stub()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

      type_place(lv, ~s(45°21'55.1"N 63°16'47.0"W))

      refute has_element?(lv, "#activity-places")
      assert has_element?(lv, "#activity-pin", "45.36531, -63.27972")
      refute_received {:mapbox, _path, _query}
    end

    test "removing the pin sends no location, as 0,0", %{conn: conn, team: team} do
      stub()
      activity = activity_fixture(team, %{d4h_activity_id: 88, coordinate: "49.1,-123.1"})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")

      assert has_element?(lv, "#activity-pin", "49.10000, -123.10000")
      lv |> element("#activity-pin-remove") |> render_click()
      refute has_element?(lv, "#activity-pin")

      lv |> form("#activity-form") |> render_submit()

      assert_received {:records, "PATCH", "/exercises/88", body}
      assert body == %{"location" => %{"latitude" => 0, "longitude" => 0}}
    end

    defp past_activities(team) do
      for _ <- 1..3,
          do: activity_fixture(team, %{address: "Hall, Surrey", coordinate: "49.1,-122.8"})

      for _ <- 1..2,
          do: activity_fixture(team, %{address: "Park, Langley", coordinate: "49.2,-122.6"})

      activity_fixture(team, %{address: "Pond, Surrey", coordinate: nil})

      # Still to come, so not counted.
      soon = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)

      activity_fixture(team, %{
        address: "Hall, Surrey",
        coordinate: "49.1,-122.8",
        started_at: soon,
        finished_at: DateTime.add(soon, 3600)
      })
    end

    test "the box lists the team's usual places, with no Mapbox search",
         %{conn: conn, team: team} do
      stub()
      past_activities(team)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

      lv |> element("#form_place") |> render_focus()

      assert has_element?(lv, "#activity-past-0", "Hall, Surrey")
      assert has_element?(lv, "#activity-past-0", "3 activities")
      assert has_element?(lv, "#activity-past-1", "Park, Langley")
      refute has_element?(lv, "#activity-past-2")

      lv |> element("#activity-past-0") |> render_click()

      refute has_element?(lv, "#activity-places")
      assert has_element?(lv, "#activity-pin", "49.10000, -122.80000")
      assert lv |> element("#form_place") |> render() =~ ~s(value="Hall, Surrey")
      refute_received {:mapbox, _path, _query}
    end

    test "typing lists the team's places that match, then Mapbox's",
         %{conn: conn, team: team} do
      stub()
      stub_mapbox()
      past_activities(team)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

      type_place(lv, "su")
      assert has_element?(lv, "#activity-past-0", "Hall, Surrey")
      assert has_element?(lv, "#activity-past-1", "Pond, Surrey")
      refute_received {:mapbox, _path, _query}

      type_place(lv, "surrey")
      render_async(lv)
      assert has_element?(lv, "#activity-past-0", "Hall, Surrey")
      assert has_element?(lv, "#activity-place-0", "Campbell Valley Regional Park")

      lv |> element("#activity-past-1") |> render_click()

      refute has_element?(lv, "#activity-pin")
      assert lv |> element("#form_place") |> render() =~ ~s(value="Pond, Surrey")
    end

    defp bookmark(team, title, address, coordinate) do
      Repo.insert!(%LocationBookmark{
        team_id: team.id,
        d4h_location_bookmark_id: System.unique_integer([:positive]),
        title: title,
        address: address,
        coordinate: coordinate
      })
    end

    test "a bookmark names the place near it, and typing finds one no activity used (#614)",
         %{conn: conn, team: team} do
      stub()
      stub_mapbox()
      past_activities(team)
      bookmark(team, "!!!! Hall", "17543 20 Ave, Surrey", "49.10050,-122.80050")
      bookmark(team, "Office", "123 Main St, Surrey", "49.19000,-122.85000")
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

      lv |> element("#form_place") |> render_focus()
      # As the team wrote it, the ! they sort with in D4H too.
      assert has_element?(lv, "#activity-past-0 .place-name", "!!!! Hall")
      assert has_element?(lv, "#activity-past-0", "Hall, Surrey · Saved place")
      assert has_element?(lv, "#activity-past-0", "3 activities")

      type_place(lv, "office")
      assert has_element?(lv, "#activity-past-0 .place-name", "Office")
      assert has_element?(lv, "#activity-past-0", "123 Main St, Surrey · Saved place")
      refute has_element?(lv, "#activity-past-0", "activities")

      lv |> element("#activity-past-0") |> render_click()
      assert has_element?(lv, "#activity-pin", "49.19000, -122.85000")
      assert lv |> element("#form_place") |> render() =~ ~s(value="123 Main St, Surrey")
    end

    test "the x empties the box and its pin, and lists the team's places again",
         %{conn: conn, team: team} do
      stub()
      past_activities(team)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")
      lv |> element("#form_place") |> render_focus()
      lv |> element("#activity-past-0") |> render_click()
      assert has_element?(lv, "#activity-pin")
      assert has_element?(lv, "#activity-place-clear")

      # What the x's sarduty:clear does in the browser.
      lv
      |> form("#activity-form")
      |> render_change(%{
        "form" => %{"place" => "", "coordinate" => ""},
        "_target" => ["form", "place"]
      })

      refute has_element?(lv, "#activity-pin")
      assert has_element?(lv, "#activity-past-0", "Hall, Surrey")
    end

    test "a Mapbox failure lists nothing", %{conn: conn, team: team} do
      Req.Test.stub(App.Adapter.Mapbox, &Plug.Conn.send_resp(&1, 401, "{}"))
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

      type_place(lv, "campbell valley")
      render_async(lv)

      refute has_element?(lv, "#activity-places")
    end
  end

  describe "a D4H team (#585)" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "d4h_key"}})
      %{conn: log_in_user(conn, user), team: team}
    end

    # D4H's writes, in the order they were made.
    defp writes do
      receive do
        {:records, method, path, body} -> [{method, path, body} | writes()]
      after
        0 -> []
      end
    end

    test "a new activity is a draft with no one's attendance and a cleaned description",
         %{conn: conn, team: team} do
      stub()
      {:ok, list, _html} = live(conn, ~p"/teams/#{team}/activities")
      assert has_element?(list, "#activity-add")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

      # As Trix writes it: a blank line in a div, and a list. The editor's input is hidden,
      # so the test sends it with the submit.
      description =
        ~s(<div>Bring a <strong style="color: red">headlamp</strong>.<br><br>Map &amp; compass too.</div><ul><li>Rope</li></ul>)

      lv
      |> form("#activity-form",
        form: %{
          title: "SAR Duty test",
          starts_at: "2026-12-12T09:00",
          ends_at: "2026-12-12T12:00"
        }
      )
      |> render_submit(%{form: %{description: description}})

      assert [{"POST", "/exercises", body} | _rest] = writes()
      assert body["fullTeam"] == false
      assert body["shared"] == false

      assert body["description"] ==
               "<p>Bring a <strong>headlamp</strong>.</p><p>Map &amp; compass too.</p><ul><li>Rope</li></ul>"

      assert [%ChangeSetRow{action: :create_activity, status: :applied}] = edit_rows(team)
    end

    test "a published activity only unpublishes, and there is no delete",
         %{conn: conn, team: team} do
      stub()

      activity =
        activity_fixture(team, %{
          title: "Practice",
          d4h_activity_id: 88,
          is_published: true,
          description: "<p>Bring a headlamp.</p>"
        })

      {:ok, page, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
      assert has_element?(page, "#activity-actions #activity-edit", "Change activity")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")
      refute has_element?(lv, "#activity-delete")
      assert has_element?(lv, "#activity-delete-elsewhere", "Delete it in D4H.")
      assert has_element?(lv, "#activity-published-locked")
      assert has_element?(lv, "#activity-form fieldset[disabled] #form_title")
      assert has_element?(lv, ~s(#form_description[value="<p>Bring a headlamp.</p>"]))

      lv |> form("#activity-form", form: %{published: false}) |> render_submit()

      assert [{"POST", "/exercises/88/publish", %{"published" => false}} | _sync] = writes()
    end

    # D4H answers 409 to publishing an activity that has not happened (Andrew, 2026-10-25).
    test "only a finished activity is published", %{conn: conn, team: team} do
      stub()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")
      later = DateTime.utc_now() |> DateTime.add(2, :day) |> Calendar.strftime("%Y-%m-%dT%H:%M")
      ended = DateTime.utc_now() |> DateTime.add(-2, :day) |> Calendar.strftime("%Y-%m-%dT%H:%M")

      started =
        DateTime.utc_now() |> DateTime.add(-3, :day) |> Calendar.strftime("%Y-%m-%dT%H:%M")

      lv
      |> form("#activity-form",
        form: %{title: "Practice", starts_at: started, ends_at: later, published: true}
      )
      |> render_submit()

      assert has_element?(lv, "#activity-form .error-summary", "Publish it once it has finished.")
      assert writes() == []

      lv
      |> form("#activity-form",
        form: %{title: "Practice", starts_at: started, ends_at: ended, published: true}
      )
      |> render_submit()

      assert {"POST", "/exercises/88/publish", %{"published" => true}} in writes()
    end

    test "a description with a link and a list is in the editor", %{conn: conn, team: team} do
      stub()

      html =
        ~s(<p>See <a href="https://example.com/map">the map</a>.</p>\n<ul>\n<li>Rope</li>\n</ul>)

      activity = activity_fixture(team, %{d4h_activity_id: 88, description: html})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")
      refute has_element?(lv, "#activity-description-locked")
      assert has_element?(lv, "#form_description-rich-text trix-editor[input=form_description]")

      cleaned =
        ~s(<p>See <a href="https://example.com/map">the map</a>.</p><ul><li>Rope</li></ul>)

      assert has_element?(lv, "#form_description[value='#{cleaned}']")

      lv |> form("#activity-form", form: %{title: "Rope practice"}) |> render_submit()

      assert [{"PATCH", "/exercises/88", body} | _rest] = writes()
      assert body == %{"referenceDescription" => "Rope practice"}
    end

    test "a description the editor can't hold is shown and never sent",
         %{conn: conn, team: team} do
      stub()
      html = ~s(<p>See <a href="https://example.com/map">the map</a>.</p><hr><p>Rope</p>)
      activity = activity_fixture(team, %{d4h_activity_id: 88, description: html})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")
      assert has_element?(lv, "#activity-description-locked a", "the map")
      refute has_element?(lv, "#form_description")

      lv |> form("#activity-form", form: %{title: "Rope practice"}) |> render_submit()

      assert [{"PATCH", "/exercises/88", body} | _rest] = writes()
      assert body == %{"referenceDescription" => "Rope practice"}
    end
  end

  test "another team's activity 404s", %{conn: conn, team: team} do
    other = activity_fixture(team_fixture())

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/teams/#{team}/activities/#{other.id}/edit")
    end
  end
end
