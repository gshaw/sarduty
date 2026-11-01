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
    assert has_element?(lv, ~s|#activity-cancel[href="#{~p"/teams/#{team}/activities"}"]|)

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

    assert html =~ "Added Missing hiker."

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

  defp template_with_details(team, attrs \\ %{}) do
    group = group_fixture(team, %{title: "Instructors"})

    for name <- ["Dana", "Lee"],
        do: group_member_fixture(group, member_fixture(team, %{name: name}))

    radio = equipment_item_fixture(team, %{title: "Radio kit A"})
    gone = equipment_item_fixture(team, %{title: "Old radio", status: "retired"})
    rope = tag_fixture(team, "Rope")

    template =
      template_fixture(team, "Monday night training", [{radio, 150}, {gone, 60}], [rope], [group])

    template
    |> Ecto.Changeset.change(
      Map.merge(
        %{
          activity_kind: "exercise",
          start_time: ~T[19:00:00],
          duration_minutes: 150,
          place: "Hall",
          hours: "secondary",
          description: "<div>Bring a radio.</div>"
        },
        attrs
      )
    )
    |> Repo.update!()
    |> then(&%{template: &1, group: group, radio: radio, gone: gone, rope: rope})
  end

  defp pick_template(lv, template),
    do:
      lv
      |> form("#activity-form", form: %{template_id: template.id})
      |> render_change(%{"_target" => ["form", "template_id"]})

  test "picking a template fills Add activity and lists what saving adds (#747)",
       %{conn: conn, team: team} do
    %{template: template, radio: radio, gone: gone, group: group} = template_with_details(team)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")
    assert has_element?(lv, "#form_published")
    refute has_element?(lv, "#activity-template-adds")
    refute has_element?(lv, "#activity-template-summary")

    pick_template(lv, template)
    {today, _time} = Service.Convert.utc_to_local(DateTime.utc_now(), team.timezone)

    assert has_element?(lv, ~s|#form_title[value="Monday night training"]|)
    assert has_element?(lv, ~s|#form_starts_at[value="#{today}T19:00"]|)
    assert has_element?(lv, ~s|#form_ends_at[value="#{today}T21:30"]|)
    assert has_element?(lv, ~s|#form_hours option[value="secondary"][selected]|)
    refute has_element?(lv, "#form_published")
    assert has_element?(lv, "#activity-template-items #item-#{radio.id}")
    refute has_element?(lv, "#activity-template-items #item-#{gone.id}")
    assert has_element?(lv, "#activity-template-tags", "Rope")

    # Finish follows Start.
    next_week = Date.add(today, 7)
    change_start(lv, "#{next_week}T18:30")
    assert has_element?(lv, ~s|#form_ends_at[value="#{next_week}T21:00"]|)
    assert has_element?(lv, "#activity-template-groups #group-#{group.id}-members", "2")

    assert has_element?(
             lv,
             "#activity-template-summary",
             "Saving also adds 1 item, 1 tag, and the members of 1 group, listed under the form."
           )

    # A date gone by leaves the groups out, as Apply a template does.
    change_start(lv, "2020-11-02T19:00")
    assert has_element?(lv, ~s|#form_ends_at[value="2020-11-02T21:30"]|)
    refute has_element?(lv, "#activity-template-groups")
    assert has_element?(lv, "#activity-template-groups-passed", "Nov 2 has passed.")
    assert has_element?(lv, "#activity-template-summary", "Saving also adds 1 item and 1 tag,")

    # Start was changed, so None asks before it empties the form.
    pick_none(lv)
    assert has_element?(lv, "#activity-template-switch", "Start over with no template?")
    render_hook(lv, "start-over", %{})

    refute has_element?(lv, "#activity-template-switch")
    assert has_element?(lv, ~s|#form_ends_at:not([value])|)
    assert has_element?(lv, "#form_published")
    refute has_element?(lv, "#activity-template-adds")
  end

  test "switching templates starts the form over, asking in a dialog when something was changed",
       %{conn: conn, team: team} do
    %{template: monday} = template_with_details(team)
    truck = template_fixture(team, "Truck check")
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

    # Nothing changed: Truck check replaces Monday night training whole.
    pick_template(lv, monday)
    pick_template(lv, truck)
    refute has_element?(lv, "#activity-template-switch")
    assert has_element?(lv, ~s|#form_title[value="Truck check"]|)
    assert has_element?(lv, ~s|#form_place:not([value])|)

    lv |> form("#activity-form", form: %{title: "Truck check, both trucks"}) |> render_change()
    pick_template(lv, monday)
    assert has_element?(lv, "#activity-template-switch", "Start over with Monday night training?")

    # Cancel keeps the changes and puts Truck check back.
    render_hook(lv, "keep-changes", %{})
    refute has_element?(lv, "#activity-template-switch")
    assert has_element?(lv, ~s|#form_template_id option[value="#{truck.id}"][selected]|)
    assert has_element?(lv, ~s|#form_title[value="Truck check, both trucks"]|)

    pick_template(lv, monday)
    render_hook(lv, "start-over", %{})
    assert has_element?(lv, ~s|#form_title[value="Monday night training"]|)
    assert has_element?(lv, ~s|#form_place[value="Hall"]|)
  end

  defp pick_none(lv),
    do:
      lv
      |> form("#activity-form", form: %{template_id: ""})
      |> render_change(%{"_target" => ["form", "template_id"]})

  defp change_start(lv, starts_at),
    do:
      lv
      |> form("#activity-form", form: %{starts_at: starts_at})
      |> render_change(%{"_target" => ["form", "starts_at"]})

  test "the template's page opens Add activity with it picked", %{conn: conn, team: team} do
    %{template: template} = template_with_details(team)
    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/templates/#{template.id}")
    path = ~p"/teams/#{team}/activities/new?template=#{template.id}"
    assert has_element?(page, ~s|#template-add-activity[href="#{path}"]|)

    {:ok, lv, _html} = live(conn, path)
    assert has_element?(lv, ~s|#form_title[value="Monday night training"]|)
    assert has_element?(lv, "#activity-template-adds")
  end

  test "saving with a template adds the activity, then its tags and members (#747)",
       %{conn: conn, team: team} do
    %{template: template, rope: rope} = template_with_details(team, %{start_time: ~T[09:00:00]})
    date = Date.utc_today() |> Date.add(7)
    stub_template_add(team, date)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")
    pick_template(lv, template)
    change_start(lv, "#{date}T09:00")
    lv |> form("#activity-form") |> render_submit()

    assert_received {:write, "/exercises", %{"referenceDescription" => "Monday night training"}}
    assert_received {:write, "/exercises/88/tags", %{"tagIds" => [2]}}
    assert_received {:write, "/exercises/88/tags", %{"tagIds" => tag_ids}}
    assert rope.d4h_tag_id in tag_ids

    for _ <- 1..2,
        do: assert_received({:write, "/attendance", %{"status" => "REQUESTED"}})

    {path, flash} = assert_redirect(lv)
    assert path =~ ~r{/activities/\d+$}
    assert flash["info"] =~ "Added Monday night training."
    assert flash["info"] =~ "1 tag added."
    assert flash["info"] =~ "2 members added."
  end

  test "with a template, the activity is added unpublished, with the template's fields",
       %{conn: conn, team: team} do
    field = custom_field_fixture(team, %{target: "exercise", title: "Lead instructor"})
    %{template: template} = template_with_details(team, %{start_time: ~T[09:00:00]})
    id = Integer.to_string(field.d4h_custom_field_id)
    template = template |> Ecto.Changeset.change(custom_values: %{id => "Dana"}) |> Repo.update!()
    date = Date.utc_today() |> Date.add(-7)
    stub_template_add(team, date)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")
    pick_template(lv, template)
    assert has_element?(lv, "#activity-template-fields", "Dana")
    change_start(lv, "#{date}T09:00")
    lv |> form("#activity-form") |> render_submit()

    assert_received {:write, "/exercises/88/publish", %{"published" => false}}
    refute_received {:write, "/exercises/88/publish", %{"published" => true}}
    refute_received {:write, "/attendance", _json}

    {_path, flash} = assert_redirect(lv)
    assert flash["info"] =~ "1 field filled in."
    assert flash["info"] =~ "Its groups were left out: the activity has started."
  end

  # Records adds activity 88 on `date`, 09:00 to 11:30, and takes every write after it.
  defp stub_template_add(team, date) do
    starts_at = Service.Convert.local_to_utc(date, ~T[09:00:00], team.timezone)
    ends_at = DateTime.add(starts_at, 150, :minute)

    activity =
      RecordsStub.activity_json(88, %{
        "referenceDescription" => "Monday night training",
        "startsAt" => DateTime.to_iso8601(starts_at),
        "endsAt" => DateTime.to_iso8601(ends_at),
        "updatedAt" => DateTime.to_iso8601(DateTime.utc_now())
      })

    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      # The sync after the add copies it; here the copy has it at once.
      if {conn.method, path} == {"POST", "/exercises"} do
        activity_fixture(team, %{
          d4h_activity_id: 88,
          title: "Monday night training",
          started_at: starts_at,
          finished_at: ends_at,
          tags: ["Secondary Hours"]
        })
      end

      case {conn.method, path} do
        {"GET", "/exercises/88"} -> Req.Test.json(conn, activity)
        {"GET", "/exercises"} -> page(conn, [activity])
        {"GET", "/tags"} -> page(conn, RecordsStub.tags_json())
        {"GET", _path} -> page(conn, [])
        {_write, path} -> written(conn, test_pid, path, body, activity)
      end
    end)
  end

  defp page(conn, results),
    do: Req.Test.json(conn, %{"results" => results, "totalSize" => length(results), "page" => 0})

  defp written(conn, test_pid, path, body, activity) do
    json = if body == "", do: nil, else: Jason.decode!(body)
    send(test_pid, {:write, path, json})

    if path == "/attendance",
      do:
        Req.Test.json(conn, %{
          "id" => System.unique_integer([:positive]),
          "activity" => %{"resourceType" => "Exercise", "id" => 88},
          "member" => %{"id" => json["memberId"]},
          "status" => json["status"],
          "startsAt" => json["startsAt"],
          "endsAt" => json["endsAt"]
        }),
      else: Req.Test.json(conn, activity)
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

    assert has_element?(
             lv,
             ~s|#activity-cancel[href="#{~p"/teams/#{team}/activities/#{activity.id}"}"]|
           )

    lv
    |> form("#activity-form", form: %{title: "Rope practice", hours: "secondary"})
    |> render_submit()

    assert_received {:records, "PATCH", "/exercises/88",
                     %{"referenceDescription" => "Rope practice"} = body}

    assert map_size(body) == 1
    assert_received {:records, "POST", "/exercises/88/tags", %{"tagIds" => [2]}}

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
    refute page |> element("#activity-delete") |> render() =~ "data-confirm-check"
    page |> element("#activity-delete") |> render_click()

    assert_received {:records, "DELETE", "/exercises/88", nil}
    assert Repo.reload!(activity).deleted_at
  end

  describe "Enough at and Full at (#447)" do
    test "a numbers-only save sends nothing, and History says from what to what",
         %{conn: conn, team: team} do
      stub()
      # The refresh's changeset never takes the numbers, so the fixture can't either.
      activity =
        team
        |> activity_fixture(%{title: "Practice", d4h_activity_id: 88})
        |> Ecto.Changeset.change(enough_at: 8)
        |> Repo.update!()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")
      assert has_element?(lv, ~s|#form_enough_at[value="8"]|)

      lv |> form("#activity-form", form: %{enough_at: "10", full_at: "14"}) |> render_submit()

      refute_received {:records, _method, _path, _body}
      assert %{enough_at: 10, full_at: 14} = Repo.reload!(activity)

      assert [%ChangeSetRow{action: :update_activity, status: :applied} = row] = edit_rows(team)
      assert row.new_value == %{"enough_at" => 10, "full_at" => 14}

      {:ok, history, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/history")
      assert render(history) =~ "Enough at changed from 8 to 10. Full at set to 14"
    end

    test "a mixed save sends the title alone, then sets the numbers",
         %{conn: conn, team: team} do
      stub()
      activity = activity_fixture(team, %{title: "Practice", d4h_activity_id: 88})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")

      lv
      |> form("#activity-form", form: %{title: "Rope practice", full_at: "14"})
      |> render_submit()

      assert_received {:records, "PATCH", "/exercises/88", body}
      assert body == %{"referenceDescription" => "Rope practice"}
      assert Repo.reload!(activity).full_at == 14

      {:ok, history, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/history")
      assert render(history) =~ "Title changed from Practice to Rope practice. Full at set to 14"
    end

    test "Full at under Enough at is refused, in the summary too", %{conn: conn, team: team} do
      activity = activity_fixture(team, %{d4h_activity_id: 88})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")

      html =
        lv |> form("#activity-form", form: %{enough_at: "10", full_at: "8"}) |> render_submit()

      assert html =~ "Enter 10 or more, since Enough at is 10."
      assert has_element?(lv, ".error-summary", "Enter 10 or more")
    end

    test "Add activity from a template takes its numbers, on the add's own row",
         %{conn: conn, team: team} do
      %{template: template} =
        template_with_details(team, %{start_time: ~T[09:00:00], enough_at: 10})

      date = Date.utc_today() |> Date.add(7)
      stub_template_add(team, date)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")
      pick_template(lv, template)
      assert has_element?(lv, ~s|#form_enough_at[value="10"]|)
      change_start(lv, "#{date}T09:00")
      lv |> form("#activity-form") |> render_submit()
      {_path, _flash} = assert_redirect(lv)

      assert %{enough_at: 10, full_at: nil} =
               Repo.get_by!(App.Model.Activity, team_id: team.id, d4h_activity_id: 88)

      assert [%ChangeSetRow{action: :create_activity} = row] = edit_rows(team)
      assert row.new_value["enough_at"] == 10
    end

    test "when the copy hasn't caught up, the flash says to set them with Change activity",
         %{conn: conn, team: team} do
      stub()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

      lv
      |> form("#activity-form",
        form: %{
          title: "Pancake breakfast",
          starts_at: "2026-11-07T09:00",
          ends_at: "2026-11-07T13:00",
          enough_at: "10"
        }
      )
      |> render_submit()

      {path, flash} = assert_redirect(lv)
      assert path == ~p"/teams/#{team}/activities"

      assert flash["error"] ==
               "Added Pancake breakfast. Set Enough at and Full at with Change activity once it shows."
    end
  end

  test "deleting an activity with attendance asks for the box ticked (#651)",
       %{conn: conn, team: team} do
    started = DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:second)
    activity = activity_fixture(team, %{started_at: started})
    attendance_fixture(activity, member_fixture(team))

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
    button = page |> element("#activity-delete") |> render()

    assert button =~ ~s(data-confirm-check="I understand the attendance for 1 member is lost.")
    assert button =~ "Its attendance for 1 member stops counting."
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
      # D4H won't publish one whose tracking number is null.
      assert body["trackingNumber"] == ""

      assert body["description"] ==
               "<p>Bring a <strong>headlamp</strong>.</p><p>Map &amp; compass too.</p><ul><li>Rope</li></ul>"

      assert [%ChangeSetRow{action: :create_activity, status: :applied}] = edit_rows(team)
    end

    test "Change activity links to Change fields, with the Fields tab's count (#705)",
         %{conn: conn, team: team} do
      custom_field_fixture(team, %{
        d4h_custom_field_id: 420,
        title: "Primary Cause",
        required: true
      })

      custom_field_fixture(team, %{
        d4h_custom_field_id: 454,
        title: "Agency File #",
        required: true
      })

      activity =
        activity_fixture(team, %{
          activity_kind: "incident",
          is_published: false,
          custom_values: %{"454" => "PROS 1"}
        })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")

      refute has_element?(lv, "#custom-field-420")

      assert has_element?(
               lv,
               "#activity-fields-missing-count",
               "1 of 2 needed to publish is empty."
             )

      assert has_element?(
               lv,
               ~s(#activity-fields-change[href="/teams/#{team.subdomain}/activities/#{activity.id}/fields/edit"])
             )

      {:ok, new, _html} = live(conn, ~p"/teams/#{team}/activities/new")
      refute has_element?(new, "#activity-fields")
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

      refute has_element?(page, "#activity-delete")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")
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
