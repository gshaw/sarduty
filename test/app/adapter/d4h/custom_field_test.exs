defmodule App.Adapter.D4H.CustomFieldTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.CustomField
  alias App.Adapter.D4H.Parse

  # Shaped like South Fraser's (read 2026-10-28), not its real ids.
  @city %{
    "id" => 888,
    "owner" => %{"id" => 422, "resourceType" => "Team"},
    "targetResourceType" => "Incident",
    "ordering" => 3,
    "title" => "City - Reporting",
    "type" => "SINGLE_CHOICE",
    "restricted" => "RESTRICTED",
    "memberPrivacy" => "HIDDEN",
    "hint" => "",
    "mandatory" => true,
    "archivedAt" => nil,
    "valueUnits" => nil,
    "bundle" => nil,
    "createdAt" => "2020-07-29T20:25:34.000Z",
    "searchable" => true,
    "frozen" => false,
    "options" => [
      %{
        "id" => 1,
        "ordering" => 0,
        "label" => "Surrey",
        "archivedAt" => nil,
        "owner" => %{"id" => 422, "resourceType" => "Team"}
      },
      %{"id" => 2, "ordering" => 1, "label" => "Delta", "archivedAt" => "2026-01-01T00:00:00Z"}
    ]
  }

  test "builds an incident field with its options" do
    field = CustomField.build(@city)

    assert field.d4h_custom_field_id == 888
    assert field.target == "incident"
    assert field.field_type == "single_choice"
    assert field.required
    assert field.restricted
    assert field.member_privacy == "hidden"
    assert field.hint == nil
    assert {field.owner_type, field.owner_id} == {"Team", 422}
    assert {field.d4h_bundle_id, field.searchable, field.frozen} == {nil, true, false}
    assert field.d4h_created_at == ~U[2020-07-29 20:25:34Z]

    assert field.options == [
             %{
               "id" => 1,
               "label" => "Surrey",
               "ordering" => 0,
               "archived" => false,
               "owner_type" => "Team",
               "owner_id" => 422
             },
             %{
               "id" => 2,
               "label" => "Delta",
               "ordering" => 1,
               "archived" => true,
               "owner_type" => nil,
               "owner_id" => nil
             }
           ]
  end

  test "a field in a bundle keeps the bundle's id (#872)" do
    field =
      CustomField.build(%{@city | "bundle" => %{"id" => 43, "resourceType" => "ResourceBundle"}})

    assert field.d4h_bundle_id == 43
  end

  test "an organisation's member field, unrestricted" do
    field =
      CustomField.build(%{
        @city
        | "targetResourceType" => "Member",
          "owner" => %{"id" => 7, "resourceType" => "Organisation"},
          "restricted" => "UNRESTRICTED",
          "memberPrivacy" => "EDITABLE",
          "type" => "DATE",
          "options" => []
      })

    assert field.target == "member"
    refute field.restricted
    assert field.member_privacy == "editable"
    assert field.owner_type == "Organisation"
  end

  test "a field on the team itself is built (#1056 step 5)" do
    field = CustomField.build(%{@city | "targetResourceType" => "Team"})
    assert field.target == "team"
    assert CustomField.d4h_target("team") == "Team"
  end

  test "a target SAR Duty doesn't copy builds nothing" do
    for target <- ~w(HealthSafetyReport PersonInvolved IncidentWeather) do
      assert CustomField.build(%{@city | "targetResourceType" => target}) == nil
    end
  end

  test "values become a map by field id, leaving out empty ones" do
    values = [
      %{"customField" => %{"id" => 888, "type" => "SINGLE_CHOICE"}, "value" => [1]},
      %{"customField" => %{"id" => 454, "type" => "TEXT"}, "value" => "PROS 2026-1"},
      %{"customField" => %{"id" => 455, "type" => "TEXT"}, "value" => ""},
      %{"customField" => %{"id" => 421, "type" => "SINGLE_CHOICE"}, "value" => []},
      %{"customField" => %{"id" => 422, "type" => "NUMBER"}, "value" => nil}
    ]

    assert Parse.custom_values(values) == %{"888" => [1], "454" => "PROS 2026-1"}
    assert Parse.custom_values(nil) == %{}
  end
end
