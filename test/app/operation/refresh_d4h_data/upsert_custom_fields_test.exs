defmodule App.Operation.RefreshD4HData.UpsertCustomFieldsTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle
  alias App.Operation.RefreshD4HData.UpsertCustomFields

  @now ~U[2026-10-28 12:00:00.000000Z]

  defp field(id, title, attrs \\ %{}),
    do:
      struct!(
        %D4H.CustomField{
          d4h_custom_field_id: id,
          title: title,
          target: "incident",
          field_type: "text"
        },
        attrs
      )

  defp bundle(id, title),
    do: %D4H.ResourceBundle{
      d4h_bundle_id: id,
      title: title,
      target: "incident",
      owner_type: "Organisation",
      owner_id: 7
    }

  test "keeps a copy of the fields, updates them, and deletes the ones D4H dropped" do
    team = team_fixture()
    other_team = team_fixture()
    UpsertCustomFields.save(other_team.id, [], [field(1, "Other team's")], @now)

    UpsertCustomFields.save(team.id, [], [field(1, "Area"), field(2, "City")], @now)

    UpsertCustomFields.save(
      team.id,
      [],
      [field(1, "Area searched", %{required: true, owner_type: "Organisation", owner_id: 7})],
      @now
    )

    assert [area] = CustomField.get_all(team.id, "incident")
    assert {area.title, area.required, area.owner_type} == {"Area searched", true, "Organisation"}
    assert CustomField.organisation?(area)
    assert [_] = CustomField.get_all(other_team.id, "incident")
  end

  test "keeps each field's bundle, and a field whose bundle D4H dropped joins none (#872)" do
    team = team_fixture()
    kms = field(1, "Primary Cause", %{d4h_bundle_id: 43, frozen: true, searchable: true})

    UpsertCustomFields.save(
      team.id,
      [bundle(43, "KMS Data"), bundle(179, "Natural disasters")],
      [kms, field(2, "Area", %{d4h_created_at: ~U[2024-03-04 18:00:00Z]})],
      @now
    )

    assert [area, cause] = CustomField.get_all(team.id, "incident")
    assert {cause.bundle.title, cause.frozen, cause.searchable} == {"KMS Data", true, true}
    assert {area.bundle, area.d4h_created_at} == {nil, ~U[2024-03-04 18:00:00Z]}

    UpsertCustomFields.save(team.id, [bundle(43, "KMS")], [kms], @now)
    assert [%{bundle: %{title: "KMS"}}] = CustomField.get_all(team.id, "incident")

    UpsertCustomFields.save(team.id, [], [kms], @now)
    assert [%{bundle: nil}] = CustomField.get_all(team.id, "incident")
    assert Repo.all(CustomFieldBundle) == []
  end

  test "a SAR Duty Records team's fields and bundles come from Records, as a D4H team's do" do
    team = team_fixture(%{d4h_api_host: D4H.records_host(), d4h_access_key: "key"})

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      assert conn.host == D4H.records_host()

      case Path.basename(conn.request_path) do
        "custom-fields" ->
          Req.Test.json(conn, %{
            "results" => [%{"id" => 7, "targetResourceType" => "Member", "title" => "Call sign"}],
            "totalSize" => 1
          })

        "resource-bundles" ->
          Req.Test.json(conn, %{
            "results" => [
              %{
                "id" => 3,
                "title" => "Demographics",
                "target" => %{"resourceType" => "CustomField", "subResourceType" => "Member"}
              }
            ],
            "totalSize" => 1
          })
      end
    end)

    context = D4H.build_context_from_team(team)

    assert [%D4H.CustomField{d4h_custom_field_id: 7, target: "member"}] =
             D4H.fetch_custom_fields(context)

    assert [%D4H.ResourceBundle{d4h_bundle_id: 3, target: "member"}] =
             D4H.fetch_resource_bundles(context)
  end
end
