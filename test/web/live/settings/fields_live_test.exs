defmodule Web.Settings.FieldsLiveTest do
  use Web.ConnCase, async: true

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Operation.RefreshD4HData.UpsertCustomFields

  defp field(id, title, attrs),
    do:
      struct!(%D4H.CustomField{d4h_custom_field_id: id, title: title, field_type: "text"}, attrs)

  defp option(id, label, owner),
    do: %{
      "id" => id,
      "label" => label,
      "ordering" => id,
      "archived" => false,
      "owner_type" => elem(owner, 0),
      "owner_id" => elem(owner, 1)
    }

  defp save(team, bundles, fields),
    do: UpsertCustomFields.save(team.id, bundles, fields, DateTime.utc_now())

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), team: team}
  end

  test "lists each kind's fields with what D4H says about them, bundles under their titles",
       %{conn: conn, team: team} do
    kms = %D4H.ResourceBundle{d4h_bundle_id: 43, title: "KMS Data", target: "incident"}

    save(team, [kms], [
      field(1, "Agency", %{
        target: "incident",
        field_type: "single_choice",
        required: true,
        hint: "The agency that asked for SAR.",
        owner_type: "Organisation",
        owner_id: 7,
        d4h_created_at: ~U[2024-03-04 18:00:00Z],
        options: [
          option(1, "Police", {"Organisation", 7}),
          option(2, "Coast Guard", {"Team", team.d4h_team_id})
        ]
      }),
      field(2, "Primary Cause", %{target: "incident", d4h_bundle_id: 43}),
      field(3, "Team notes", %{
        target: "incident",
        field_type: "text_area",
        restricted: true,
        owner_type: "Team",
        owner_id: team.d4h_team_id
      }),
      field(4, "Old notes", %{target: "equipment", archived_at: ~U[2025-01-01 00:00:00Z]})
    ])

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields")

    [agency, cause, notes, old] =
      team.id |> CustomField.get_all_with_archived() |> Enum.sort_by(& &1.d4h_custom_field_id)

    # One kind at a time, incidents first; each field a row link to its own page, the
    # team's own first, then its organization's (#1056).
    assert has_element?(lv, "#fields-kind-incident[aria-current]", "3")
    assert has_element?(lv, "#fields-kind-equipment", "0")
    assert has_element?(lv, "#fields-incident-list-team h2", "#{team.name}'s fields")
    assert has_element?(lv, "#fields-incident-list-team #field-#{notes.id}", "Long text")
    assert has_element?(lv, "#field-#{notes.id} .badge", "Restricted")
    assert has_element?(lv, "#fields-incident-list-organization h2", "Your organization's fields")

    assert has_element?(
             lv,
             "#fields-incident-list-organization #field-#{agency.id}",
             "One choice"
           )

    assert has_element?(lv, "#field-#{agency.id} .badge-primary", "Needed to publish")
    refute has_element?(lv, "table")
    assert has_element?(lv, "#field-#{agency.id}", "The agency that asked for SAR.")
    refute has_element?(lv, "#field-#{agency.id}", "Police")

    assert has_element?(
             lv,
             "#field-#{agency.id} a.row-link[href='/teams/#{team.subdomain}/settings/fields/#{agency.id}']"
           )

    assert has_element?(lv, "#fields-incident-list-team-bundle-43", "KMS Data")
    assert has_element?(lv, "#fields-incident-list-team-bundle-43 #field-#{cause.id}")
    refute has_element?(lv, "#field-#{old.id}")

    lv |> element("#fields-kind-equipment") |> render_click()
    assert_patch(lv, ~p"/teams/#{team}/settings/fields?kind=equipment")
    assert has_element?(lv, "#archived-fields:not([open]) #field-#{old.id}")
    refute has_element?(lv, "#field-#{agency.id}")

    # A field's own page: everything about it, every choice one per line.
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{agency.id}")
    assert has_element?(lv, "h1", "Agency")
    assert has_element?(lv, "#field-hint", "The agency that asked for SAR.")
    assert has_element?(lv, "#field-type", "One choice")
    refute has_element?(lv, "#field-type", "Needed to publish")
    assert has_element?(lv, "#field-required", "Fill it in before you publish the incident.")
    assert has_element?(lv, "#field-on", "Incidents")
    assert has_element?(lv, "#field-from", "Mar 4, 2024")
    assert has_element?(lv, "#field-from", "Only Your organization can change it.")
    assert has_element?(lv, "#field-choices li", "Police")
    refute has_element?(lv, "#field-choices li", "Coast Guard")
    assert has_element?(lv, "#field-details", "#{team.name} added")
    assert has_element?(lv, "#field-details li", "Coast Guard")
    assert has_element?(lv, "#field-details", "Your team added these choices.")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{notes.id}")
    assert has_element?(lv, "#field-type", "Long text")
    assert has_element?(lv, "#field-from", team.name)
    assert has_element?(lv, "#field-from", "Only #{team.name} has this field.")
    refute has_element?(lv, "#field-required")
    assert has_element?(lv, "#field-restricted", "Only team admins see its values.")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{cause.id}")
    assert has_element?(lv, "#field-on", "under KMS Data")
  end

  test "another team's field is not found", %{conn: conn} do
    other = team_fixture()
    field = custom_field_fixture(other, %{title: "Theirs"})

    %{user: user, team: team} = user_with_team_fixture()

    assert_raise Ecto.NoResultsError, fn ->
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/fields/#{field.id}")
    end
  end

  test "member fields: who sees each one's answers, a restricted one a normal row (#1056)",
       %{conn: conn, team: team} do
    save(team, [], [
      field(630, "Radio Call Sign", %{target: "member", member_privacy: "viewable"}),
      field(631, "Areas", %{target: "member", member_privacy: "editable"}),
      field(855, "Year of birth", %{
        target: "member",
        restricted: true,
        member_privacy: "editable"
      }),
      field(856, "Notes", %{target: "member", member_privacy: "hidden"})
    ])

    [call_sign, areas, birth, notes] =
      team.id |> CustomField.get_all("member") |> Enum.sort_by(& &1.d4h_custom_field_id)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields?kind=member")

    assert has_element?(lv, "#member-fields-who", "Team admins see every member's answers.")
    assert has_element?(lv, "#field-#{call_sign.id}", "Text · Members see their own")
    assert has_element?(lv, "#field-#{areas.id}", "Members change their own")
    assert has_element?(lv, "#field-#{birth.id}", "Members change their own")
    refute has_element?(lv, "#field-#{birth.id} .badge")
    assert has_element?(lv, "#field-#{notes.id}", "Team admins only")
    refute has_element?(lv, "input[type=checkbox]")
    refute has_element?(lv, "#member-fields-form")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{birth.id}")

    assert has_element?(
             lv,
             "#field-members",
             "Each member sees their own answer and can change it."
           )

    assert has_element?(lv, "#field-members", "Team admins see every member's answer.")
    assert has_element?(lv, "#field-restricted", "restricted changes nothing in SAR Duty")
    refute render(lv) =~ "never copies"
  end

  test "fields on the team itself are a sixth kind, filled in on General (#1056)",
       %{conn: conn, team: team} do
    owner = %{owner_type: "Organisation", owner_id: 9}

    save(team, [], [
      field(701, "Duty Phone", Map.merge(owner, %{target: "team", hint: "The number to call."})),
      field(702, "Team Email Contact", Map.merge(owner, %{target: "team", restricted: true})),
      field(40, "Primary Cause", %{target: "incident"})
    ])

    [phone, email] =
      team.id |> CustomField.get_all("team") |> Enum.sort_by(& &1.d4h_custom_field_id)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields?kind=team")

    assert has_element?(lv, "#fields-kind-team", "Team")
    assert has_element?(lv, "#team-fields-who a[href='/teams/#{team.subdomain}/settings']")
    assert has_element?(lv, "#fields-team-list-organization #field-#{phone.id}", "Text")
    assert has_element?(lv, "#field-#{email.id} .badge", "Restricted")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/#{email.id}")
    assert has_element?(lv, "#field-on", "Team")
    assert has_element?(lv, "#field-restricted", "Members and your organization never do.")
  end

  test "says when the team has no fields", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields")

    assert has_element?(lv, "#no-fields")
    refute has_element?(lv, "#member-fields-form")
  end
end
