defmodule App.Operation.RefreshD4HData.UpsertCustomFieldsTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.CustomField
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

  test "keeps a copy of the fields, updates them, and deletes the ones D4H dropped" do
    team = team_fixture()
    other_team = team_fixture()
    UpsertCustomFields.save(other_team.id, [field(1, "Other team's")], @now)

    UpsertCustomFields.save(team.id, [field(1, "Area"), field(2, "City")], @now)

    UpsertCustomFields.save(
      team.id,
      [field(1, "Area searched", %{required: true, owner_type: "Organisation", owner_id: 7})],
      @now
    )

    assert [area] = CustomField.get_all(team.id, "incident")
    assert {area.title, area.required, area.owner_type} == {"Area searched", true, "Organisation"}
    assert CustomField.organisation?(area)
    assert [_] = CustomField.get_all(other_team.id, "incident")
  end

  test "a SAR Duty Records team has no custom fields, and D4H isn't asked" do
    team = team_fixture(%{d4h_api_host: D4H.records_host(), d4h_access_key: "key"})
    Req.Test.stub(App.Adapter.D4H, fn _conn -> flunk("Records was asked for custom fields") end)

    assert team |> D4H.build_context_from_team() |> D4H.fetch_custom_fields() == []
  end
end
