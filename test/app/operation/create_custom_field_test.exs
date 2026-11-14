defmodule App.Operation.CreateCustomFieldTest do
  use ExUnit.Case, async: true

  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle
  alias App.Model.Team
  alias App.Operation.CreateCustomField
  alias App.ViewModel.CustomFieldFormViewModel

  @fields [
    %CustomField{
      id: 1,
      target: "incident",
      title: "Agency",
      owner_type: "Organisation",
      ordering: 40
    },
    %CustomField{id: 2, target: "incident", title: "Team notes", owner_type: "Team", ordering: 4},
    %CustomField{id: 3, target: "member", title: "Call sign", owner_type: "Team", ordering: 9}
  ]

  @bundles [
    %CustomFieldBundle{
      d4h_bundle_id: 6,
      title: "Debrief",
      target: "incident",
      owner_type: "Team",
      ordering: 2
    }
  ]

  defp form(attrs),
    do: Map.merge(%{CustomFieldFormViewModel.new("incident") | title: "Debrief held"}, attrs)

  test "a field goes after the team's own of its kind, with its live choices" do
    form =
      form(%{
        field_type: "single_choice",
        choices: [
          %{"id" => nil, "label" => "Yes", "archived" => false},
          %{"id" => nil, "label" => "Gone", "archived" => true},
          %{"id" => nil, "label" => "No", "archived" => false}
        ],
        hint: "Within 48 hours",
        required: true
      })

    assert [row] = CreateCustomField.plan(form, @fields, @bundles)
    assert row.action == :create_custom_field

    assert row.new_value == %{
             "target" => "incident",
             "title" => "Debrief held",
             "field_type" => "single_choice",
             "options" => ["Yes", "No"],
             "hint" => "Within 48 hours",
             "required" => true,
             "restricted" => false,
             "member_privacy" => "hidden",
             "ordering" => 5
           }
  end

  test "a kind's first field is at 0, and no choices go on a text field" do
    form = %{form(%{field_type: "text"}) | target: "equipment"}
    assert [%{new_value: value}] = CreateCustomField.plan(form, @fields, @bundles)
    assert value["ordering"] == 0
    refute Map.has_key?(value, "options")
    assert value["restricted"] == false
  end

  test "a bundle the team has is its id" do
    form = form(%{field_type: "text", bundle: "Debrief"})

    assert [%{new_value: %{"d4h_bundle_id" => 6}}] =
             CreateCustomField.plan(form, @fields, @bundles)
  end

  test "a new bundle name adds the bundle first, and the field waits for its id" do
    form = form(%{field_type: "text", bundle: "After action"})
    assert [bundle, field] = CreateCustomField.plan(form, @fields, @bundles)

    assert bundle.action == :create_resource_bundle

    assert bundle.new_value == %{
             "target" => "incident",
             "title" => "After action",
             "ordering" => 3
           }

    assert field.new_value["created_in_set"]
    refute Map.has_key?(field.new_value, "d4h_bundle_id")
  end

  test "a key that cannot change fields is refused, and a Records team's always can" do
    assert CreateCustomField.check_team(%Team{d4h_permissions: nil}) == :ok

    assert {:error, "This D4H access key cannot change fields. Use an Owner's key."} =
             CreateCustomField.check_team(%Team{
               d4h_permissions: %{},
               d4h_api_host: "api.ca.d4h.org"
             })
  end
end
