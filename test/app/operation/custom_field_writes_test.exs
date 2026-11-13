defmodule App.Operation.CustomFieldWritesTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.ChangeSetRow
  alias App.Model.CustomField
  alias App.Operation.ChangeCustomField
  alias App.Operation.CreateCustomField
  alias App.Operation.DeleteCustomField
  alias App.Operation.ReorderCustomFields
  alias App.RecordsStub

  # A team's own fields on a SAR Duty Records team, end to end (#1056 step 4): each
  # operation sends its change set and the copy takes Records' answer, before any sync.

  @now ~U[2026-11-13 18:00:00.000000Z]

  defp field_json(attrs \\ %{}) do
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
        "bundle" => %{"id" => 6},
        "owner" => %{"resourceType" => "Team", "id" => 2_000_000_001},
        "options" => [
          %{"id" => 43, "label" => "Yes", "ordering" => 0, "archivedAt" => nil},
          %{"id" => 44, "label" => "No", "ordering" => 1, "archivedAt" => nil}
        ]
      },
      attrs
    )
  end

  defp bundle_json,
    do: %{
      "id" => 6,
      "title" => "After action",
      "ordering" => 0,
      "target" => %{"resourceType" => "CustomField", "subResourceType" => "Incident"},
      "owner" => %{"resourceType" => "Team", "id" => 2_000_000_001}
    }

  setup do
    records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
  end

  defp add_debrief(team, user) do
    bundle = bundle_json()
    field = field_json()

    reply = fn
      "POST", "/resource-bundles", _body -> {200, bundle}
      "POST", "/custom-fields", _body -> {200, field}
    end

    RecordsStub.stub(reply)

    CreateCustomField.call(
      team,
      user,
      %{
        "target" => "incident",
        "title" => "Debrief held",
        "field_type" => "single_choice",
        "choices" => ["Yes", "No"],
        "bundle" => "After action"
      },
      @now
    )
  end

  test "adding a field adds its new bundle first, and the copy has both", %{
    team: team,
    user: user
  } do
    assert {:ok, %CustomField{} = field} = add_debrief(team, user)

    assert_received {:records, "POST", "/resource-bundles", bundle}
    assert bundle["title"] == "After action"
    assert_received {:records, "POST", "/custom-fields", body}
    assert body["resourceBundleId"] == 6

    assert body["options"] == [
             %{"label" => "Yes", "ordering" => 0},
             %{"label" => "No", "ordering" => 1}
           ]

    assert field.title == "Debrief held"
    assert field.bundle.title == "After action"
    assert Enum.map(field.options, & &1["label"]) == ["Yes", "No"]

    rows = ChangeSetRow |> where(team_id: ^team.id) |> order_by(:id) |> Repo.all()

    assert Enum.map(rows, &{&1.action, &1.status}) == [
             {:create_resource_bundle, :applied},
             {:create_custom_field, :applied}
           ]
  end

  test "a refused bundle sends no field, and the form's errors send nothing", %{
    team: team,
    user: user
  } do
    RecordsStub.stub(fn "POST", "/resource-bundles", _ ->
      {400, %{"title" => "Enter a shorter name"}}
    end)

    assert {:error, "Enter a shorter name"} =
             CreateCustomField.call(
               team,
               user,
               %{
                 "target" => "incident",
                 "title" => "Debrief held",
                 "field_type" => "text",
                 "bundle" => "After action"
               },
               @now
             )

    assert_received {:records, "POST", "/resource-bundles", _}
    refute_received {:records, "POST", "/custom-fields", _}
    assert Repo.all(CustomField) == []

    assert {:error, %Ecto.Changeset{}} =
             CreateCustomField.call(team, user, %{"target" => "incident", "title" => ""}, @now)

    refute_received {:records, _, _, _}
  end

  test "a change renames and adds choices, and archive and restore", %{team: team, user: user} do
    {:ok, field} = add_debrief(team, user)
    archived = field_json(%{"archivedAt" => "2026-11-13T18:00:00Z"})
    restored = field_json()

    reply = fn
      "PATCH", "/custom-field-options/43", _ ->
        {200, %{"id" => 43, "label" => "Yes, in person", "ordering" => 0, "archivedAt" => nil}}

      "POST", "/custom-field-options", _ ->
        {200, %{"id" => 45, "label" => "Online", "ordering" => 2, "archivedAt" => nil}}

      "PATCH", "/custom-fields/93", %{"archived" => true} ->
        {200, archived}

      "PATCH", "/custom-fields/93", %{"archived" => false} ->
        {200, restored}
    end

    RecordsStub.stub(reply)

    assert {:ok, field} =
             ChangeCustomField.call(
               team,
               user,
               field,
               %{
                 "title" => "Debrief held",
                 "bundle" => "After action",
                 "choices" => %{
                   "0" => %{"id" => "43", "label" => "Yes, in person"},
                   "1" => %{"id" => "44", "label" => "No"},
                   "2" => %{"id" => "", "label" => "Online"}
                 }
               },
               @now
             )

    refute_received {:records, "PATCH", "/custom-fields/93", _}

    assert_received {:records, "PATCH", "/custom-field-options/43",
                     %{"label" => "Yes, in person"}}

    assert_received {:records, "POST", "/custom-field-options",
                     %{"customFieldId" => 93, "label" => "Online", "ordering" => 2}}

    assert Enum.map(field.options, & &1["label"]) == ["Yes, in person", "No", "Online"]

    assert ChangeCustomField.set_archived(team, user, field, true, @now) == :ok
    assert CustomField.get_for_team!(team.id, field.id).archived_at
    assert ChangeCustomField.set_archived(team, user, field, false, @now) == :ok
    refute CustomField.get_for_team!(team.id, field.id).archived_at
  end

  test "a field with answers is archived, never deleted; one without goes", %{
    team: team,
    user: user
  } do
    {:ok, field} = add_debrief(team, user)
    RecordsStub.stub(fn "DELETE", "/custom-fields/93", _ -> {204, %{}} end)

    incident =
      activity_fixture(team, %{activity_kind: "incident", custom_values: %{"93" => [43]}})

    assert {:error, "Archive this field instead. Records have answers to it."} =
             DeleteCustomField.call(team, user, field, @now)

    refute_received {:records, "DELETE", _, _}

    incident |> Ecto.Changeset.change(custom_values: %{}) |> Repo.update!()
    assert DeleteCustomField.call(team, user, field, @now) == :ok
    assert_received {:records, "DELETE", "/custom-fields/93", _}
    assert Repo.get(CustomField, field.id) == nil
  end

  test "a new order sends each field that moved", %{team: team, user: user} do
    a =
      custom_field_fixture(team, %{
        d4h_custom_field_id: 91,
        title: "A",
        owner_type: "Team",
        ordering: 0
      })

    b =
      custom_field_fixture(team, %{
        d4h_custom_field_id: 92,
        title: "B",
        owner_type: "Team",
        ordering: 1
      })

    custom_field_fixture(team, %{title: "Agency", owner_type: "Organisation", ordering: 0})

    answers = %{
      "/custom-fields/92" => field_json(%{"id" => 92, "title" => "B", "ordering" => 0}),
      "/custom-fields/91" => field_json(%{"id" => 91, "title" => "A", "ordering" => 1})
    }

    RecordsStub.stub(fn "PATCH", path, _body -> {200, answers[path]} end)

    assert ReorderCustomFields.call(team, user, "incident", [b.id, a.id], @now) == :ok
    assert_received {:records, "PATCH", "/custom-fields/92", %{"ordering" => 0}}
    assert_received {:records, "PATCH", "/custom-fields/91", %{"ordering" => 1}}
    assert Repo.get!(CustomField, a.id).ordering == 1
  end

  test "an Editor's D4H key is refused before anything is sent" do
    %{team: team, user: user} = user_with_team_fixture(%{team: %{d4h_access_key: "key"}})
    team = team |> Ecto.Changeset.change(d4h_permissions: %{}) |> Repo.update!()

    assert {:error, "This D4H access key cannot change fields. Use an Owner's key."} =
             CreateCustomField.call(
               team,
               user,
               %{"target" => "incident", "title" => "A", "field_type" => "text"},
               @now
             )
  end
end
