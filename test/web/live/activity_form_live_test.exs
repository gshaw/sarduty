defmodule Web.ActivityFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
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

    test "a new activity is a draft with no one's attendance and an HTML description",
         %{conn: conn, team: team} do
      stub()
      {:ok, list, _html} = live(conn, ~p"/teams/#{team}/activities")
      assert has_element?(list, "#activity-add")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

      lv
      |> form("#activity-form",
        form: %{
          title: "SAR Duty test",
          starts_at: "2026-12-12T09:00",
          ends_at: "2026-12-12T12:00",
          description: "Bring a headlamp.\n\nMap & compass too."
        }
      )
      |> render_submit()

      assert [{"POST", "/exercises", body} | _rest] = writes()
      assert body["fullTeam"] == false
      assert body["shared"] == false
      assert body["description"] == "<p>Bring a headlamp.</p><p>Map &amp; compass too.</p>"
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
      assert has_element?(lv, "#form_description", "Bring a headlamp.")

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

    test "a description with formatting is shown and never sent", %{conn: conn, team: team} do
      stub()
      html = ~s(<p>See <a href="https://example.com/map">the map</a>.</p>)
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
