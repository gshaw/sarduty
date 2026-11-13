defmodule Web.Settings.FieldFormLiveTest do
  use Web.ConnCase, async: true

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.CustomField
  alias App.RecordsStub
  alias App.Repo

  # Add field, Change field, and the field page's buttons (#1056 step 4), on a SAR Duty
  # Records team, through App.RecordsStub. Never D4H.

  defp field_json(attrs) do
    Map.merge(
      %{
        "id" => 93,
        "targetResourceType" => "Incident",
        "title" => "Debrief held",
        "type" => "SINGLE_CHOICE",
        "restricted" => "UNRESTRICTED",
        "memberPrivacy" => "HIDDEN",
        "mandatory" => false,
        "ordering" => 0,
        "bundle" => nil,
        "owner" => %{"resourceType" => "Team", "id" => 2_000_000_001},
        "options" => [
          %{"id" => 43, "label" => "Yes", "ordering" => 0, "archivedAt" => nil},
          %{"id" => 44, "label" => "No", "ordering" => 1, "archivedAt" => nil}
        ]
      },
      attrs
    )
  end

  defp own_field(team, attrs \\ %{}) do
    custom_field_fixture(
      team,
      Map.merge(
        %{
          d4h_custom_field_id: 93,
          title: "Debrief held",
          field_type: "single_choice",
          owner_type: "Team",
          owner_id: team.d4h_team_id,
          options: [
            %{"id" => 43, "label" => "Yes", "ordering" => 0, "archived" => false},
            %{"id" => 44, "label" => "No", "ordering" => 1, "archived" => false},
            %{"id" => 45, "label" => "Not needed", "ordering" => 2, "archived" => true}
          ]
        },
        attrs
      )
    )
  end

  setup %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
    %{conn: log_in_user(conn, user), team: team}
  end

  test "the Fields tab offers Add field for the kind in view", %{conn: conn, team: team} do
    own_field(team, %{target: "member", field_type: "text", options: []})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields?kind=member")

    assert has_element?(lv, "#fields-who-changes", "Add and change your team's own fields here.")
    refute has_element?(lv, "#fields-key-cannot")

    assert has_element?(
             lv,
             "#field-add[href='/teams/#{team.subdomain}/settings/fields/new?kind=member']"
           )
  end

  test "adds a one-choice field to incidents", %{conn: conn, team: team} do
    RecordsStub.stub(fn "POST", "/custom-fields", _ -> {200, field_json(%{})} end)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/new?kind=incident")

    assert has_element?(lv, "#field_target option[selected][value=incident]")
    assert has_element?(lv, "#field_required")
    assert has_element?(lv, "#field_restricted")
    refute has_element?(lv, "#field-choices")
    refute has_element?(lv, "#field_member_privacy")

    lv
    |> form("#field-form", field: %{title: "Debrief held", field_type: "single_choice"})
    |> render_change()

    assert has_element?(lv, "#field-type-hint", "Pick one from a list.")
    assert has_element?(lv, "#field-choice-0-label")
    lv |> element("#field-add-choice") |> render_click()
    assert has_element?(lv, "#field-choice-1-remove")

    {:ok, page, _html} =
      lv
      |> form("#field-form",
        field: %{
          title: "Debrief held",
          field_type: "single_choice",
          choices: %{"0" => %{label: "Yes"}, "1" => %{label: "No"}}
        }
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert_received {:records, "POST", "/custom-fields", body}
    assert body["title"] == "Debrief held"
    assert body["targetResourceType"] == "Incident"
    assert Enum.map(body["options"], & &1["label"]) == ["Yes", "No"]

    field = Repo.get_by!(CustomField, team_id: team.id, d4h_custom_field_id: 93)
    assert has_element?(page, "h1", "Debrief held")
    assert has_element?(page, "#field-change[href$='/settings/fields/#{field.id}/edit']")
  end

  test "a choice field without a choice, or a taken name, sends nothing",
       %{conn: conn, team: team} do
    custom_field_fixture(team, %{title: "Agency", owner_type: "Organisation"})
    RecordsStub.stub(fn _, _, _ -> {500, %{}} end)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/new?kind=incident")

    html =
      lv
      |> form("#field-form", field: %{title: "agency", field_type: "single_choice"})
      |> render_submit()

    assert html =~ "Enter a name no other field on incidents has."
    assert has_element?(lv, "#field-choices", "Enter at least 1 choice.")
    refute_received {:records, _, _, _}
  end

  test "a member field asks what members do; no Needed to publish or Restricted",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/new?kind=member")

    assert has_element?(lv, "#field_member_privacy[value=hidden][checked]")
    assert has_element?(lv, "#field-form", "They see and change it")
    refute has_element?(lv, "#field_required")
    refute has_element?(lv, "#field_restricted")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/new?kind=equipment")
    refute has_element?(lv, "#field_required")
    refute has_element?(lv, "#field_restricted")
    refute has_element?(lv, "#field_member_privacy")
  end

  test "changes a field: facts in the lead, choices renamed and archived",
       %{conn: conn, team: team} do
    field = own_field(team)
    activity_fixture(team, %{activity_kind: "incident", custom_values: %{"93" => 43}})

    renamed = field_json(%{"title" => "Debrief"})

    reply = fn
      "PATCH", "/custom-fields/93", _ ->
        {200, renamed}

      "PATCH", "/custom-field-options/44", _ ->
        {200,
         %{"id" => 44, "label" => "No", "ordering" => 1, "archivedAt" => "2026-11-13T18:00:00Z"}}
    end

    RecordsStub.stub(reply)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{field.id}/edit")

    assert has_element?(lv, "#field-facts", "One choice, on incidents. 1 incident has an answer.")
    refute has_element?(lv, "#field_target")
    refute has_element?(lv, "#field_field_type")
    assert has_element?(lv, "#field-choice-0-archive")
    assert has_element?(lv, "#field-choice-2-restore")
    assert has_element?(lv, "#field-choice-2-label[readonly]")
    assert has_element?(lv, "#field-archive")
    refute has_element?(lv, "#field-delete")

    lv |> element("#field-choice-1-archive") |> render_click()
    assert has_element?(lv, "#field-choice-1-restore")

    {:ok, _page, _html} =
      lv
      |> form("#field-form", field: %{title: "Debrief"})
      |> render_submit()
      |> follow_redirect(conn)

    assert_received {:records, "PATCH", "/custom-fields/93", %{"title" => "Debrief"}}
    assert_received {:records, "PATCH", "/custom-field-options/44", %{"archived" => true}}
  end

  test "dragging choices sends their new order", %{conn: conn, team: team} do
    field = own_field(team)

    RecordsStub.stub(fn "PATCH", "/custom-field-options/" <> id, _ ->
      {200, %{"id" => String.to_integer(id), "label" => "x", "ordering" => 0}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{field.id}/edit")

    assert has_element?(lv, "#field-choice-list-row-option-43 [data-drag-handle]")
    assert has_element?(lv, "#field-choice-list-row-option-43 [aria-label='Move Yes']")

    lv
    |> element("#field-choice-list")
    |> render_hook("reorder-choices", %{"keys" => ["option-44", "option-43", "option-45"]})

    assert has_element?(lv, "#field-choice-0-label[value=No]")
    assert has_element?(lv, "#field-choice-1-label[value=Yes]")

    # Keys that don't name each choice once change nothing.
    lv
    |> element("#field-choice-list")
    |> render_hook("reorder-choices", %{"keys" => ["option-43"]})

    assert has_element?(lv, "#field-choice-0-label[value=No]")

    lv |> form("#field-form") |> render_submit()

    assert_received {:records, "PATCH", "/custom-field-options/44", %{"ordering" => 0}}
    assert_received {:records, "PATCH", "/custom-field-options/43", %{"ordering" => 1}}
    refute_received {:records, "PATCH", "/custom-field-options/45", _}
  end

  test "a field no record has answered offers Delete in place of Archive",
       %{conn: conn, team: team} do
    field = own_field(team)
    RecordsStub.stub(fn "DELETE", "/custom-fields/93", _ -> {204, %{}} end)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{field.id}/edit")

    assert has_element?(lv, "#field-facts", "No incident has an answer.")
    refute has_element?(lv, "#field-archive")
    assert has_element?(lv, "#field-delete[data-confirm]")

    {:ok, page, _html} =
      lv |> element("#field-delete") |> render_click() |> follow_redirect(conn)

    assert_received {:records, "DELETE", "/custom-fields/93", _}
    assert Repo.get(CustomField, field.id) == nil
    assert render(page) =~ "Deleted the Debrief held field."
  end

  test "archives a field with answers, and its page restores it", %{conn: conn, team: team} do
    field = own_field(team)
    activity_fixture(team, %{activity_kind: "incident", custom_values: nil})
    archived = field_json(%{"archivedAt" => "2026-11-13T18:00:00Z"})
    restored = field_json(%{})

    reply = fn
      "PATCH", "/custom-fields/93", %{"archived" => true} -> {200, archived}
      "PATCH", "/custom-fields/93", %{"archived" => false} -> {200, restored}
    end

    RecordsStub.stub(reply)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{field.id}/edit")

    {:ok, page, _html} =
      lv |> element("#field-archive") |> render_click() |> follow_redirect(conn)

    assert has_element?(page, "#field-archived")
    assert has_element?(page, "#field-restore")
    refute has_element?(page, "#field-change")

    page |> element("#field-restore") |> render_click()
    assert_received {:records, "PATCH", "/custom-fields/93", %{"archived" => false}}
    refute has_element?(page, "#field-archived")
    assert has_element?(page, "#field-change")
  end

  test "an organization's field has no Change field, and its form is not found",
       %{conn: conn, team: team} do
    field = custom_field_fixture(team, %{title: "Agency", owner_type: "Organisation"})
    frozen = own_field(team, %{frozen: true})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{field.id}")
    refute has_element?(lv, "#field-change")
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{frozen.id}")
    refute has_element?(lv, "#field-change")

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/settings/fields/#{field.id}/edit")
    end

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/settings/fields/#{frozen.id}/edit")
    end
  end

  test "a key that cannot change fields says why, with no Add field or Change field",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "key"}})
    team = team |> Ecto.Changeset.change(d4h_permissions: %{}) |> Repo.update!()
    field = own_field(team)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields")
    assert has_element?(lv, "#fields-key-cannot", "save a key from a D4H Owner")
    assert has_element?(lv, "#fields-key-cannot a[href$='/settings/access-key']")
    refute has_element?(lv, "#field-add")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{field.id}")
    refute has_element?(lv, "#field-change")
    assert has_element?(lv, "#field-from", "Change it in D4H.")

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/settings/fields/new")
    end
  end
end
