defmodule App.Operation.ChangeCustomFieldTest do
  use ExUnit.Case, async: true

  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle
  alias App.Model.Team
  alias App.Operation.ChangeCustomField
  alias App.ViewModel.CustomFieldFormViewModel

  @bundle %CustomFieldBundle{
    d4h_bundle_id: 6,
    title: "Debrief",
    target: "incident",
    owner_type: "Team"
  }

  defp debrief(attrs \\ %{}) do
    struct(
      %CustomField{
        id: 9,
        team_id: 1,
        d4h_custom_field_id: 93,
        target: "incident",
        title: "Debrief held",
        field_type: "single_choice",
        restricted: false,
        member_privacy: "hidden",
        owner_type: "Team",
        bundle: @bundle,
        options: [
          %{"id" => 43, "label" => "Yes", "ordering" => 0, "archived" => false},
          %{"id" => 44, "label" => "No", "ordering" => 1, "archived" => false}
        ]
      },
      attrs
    )
  end

  defp plan(field, changes, bundles \\ [@bundle]),
    do:
      ChangeCustomField.plan(
        field,
        Map.merge(CustomFieldFormViewModel.from_field(field), changes),
        bundles
      )

  test "nothing changed sends nothing" do
    assert plan(debrief(), %{}) == []
  end

  test "the field's row has only what changed, with what it was" do
    assert [row] = plan(debrief(), %{title: "Debrief", hint: "Within 48 hours", restricted: true})
    assert row.action == :update_custom_field
    assert row.d4h_record_id == 93

    assert row.new_value == %{
             "title" => "Debrief",
             "hint" => "Within 48 hours",
             "restricted" => true
           }

    assert row.old_value == %{
             "title" => "Debrief held",
             "hint" => nil,
             "restricted" => false,
             "d4h_bundle_id" => 6
           }
  end

  test "Restricted never changes on a member or equipment field" do
    call_sign =
      debrief(%{
        target: "member",
        field_type: "text",
        restricted: false,
        options: [],
        bundle: nil
      })

    assert plan(call_sign, %{restricted: true}) == []

    assert [%{new_value: %{"member_privacy" => "editable"}}] =
             plan(call_sign, %{member_privacy: "editable"})

    item = %{call_sign | target: "equipment", restricted: true}
    assert plan(item, %{restricted: false}) == []
  end

  test "Restricted changes on a field on the team itself; Needed to publish never (#1056)" do
    phone = debrief(%{target: "team", field_type: "text", options: [], bundle: nil})

    assert [%{new_value: %{"restricted" => true}}] =
             plan(phone, %{restricted: true, required: true})
  end

  test "out of a bundle, or into a new one added first" do
    assert [%{new_value: %{"d4h_bundle_id" => nil}}] = plan(debrief(), %{bundle: nil})

    assert [bundle, field] = plan(debrief(), %{bundle: "After action"})
    assert bundle.action == :create_resource_bundle
    # The applier fills in the bundle's id once it is added.
    assert field.new_value == %{"created_in_set" => true, "d4h_bundle_id" => nil}
  end

  test "choices are renamed, reordered, archived, restored, and added; never deleted" do
    field =
      debrief(%{
        options: [
          %{"id" => 43, "label" => "Yes", "ordering" => 0, "archived" => false},
          %{"id" => 44, "label" => "No", "ordering" => 1, "archived" => false},
          %{"id" => 45, "label" => "Maybe", "ordering" => 2, "archived" => true}
        ]
      })

    rows =
      plan(field, %{
        choices: [
          %{"id" => 44, "label" => "No", "archived" => false},
          %{"id" => 43, "label" => "Yes, in person", "archived" => true},
          %{"id" => 45, "label" => "Maybe", "archived" => false},
          %{"id" => nil, "label" => "Online", "archived" => false},
          %{"id" => nil, "label" => "Typo", "archived" => true},
          # Not one of the field's: never sent.
          %{"id" => 999, "label" => "Other", "archived" => false}
        ]
      })

    assert Enum.map(rows, &{&1.action, &1.d4h_record_id, &1.new_value}) == [
             {:update_custom_field_option, 44, %{"ordering" => 0, "d4h_custom_field_id" => 93}},
             {:update_custom_field_option, 43,
              %{
                "label" => "Yes, in person",
                "ordering" => 1,
                "archived" => true,
                "d4h_custom_field_id" => 93
              }},
             {:update_custom_field_option, 45,
              %{"archived" => false, "d4h_custom_field_id" => 93}},
             {:create_custom_field_option, nil,
              %{"d4h_custom_field_id" => 93, "label" => "Online", "ordering" => 3}}
           ]
  end

  test "archive and restore keep every answer" do
    assert %{
             action: :update_custom_field,
             new_value: %{"archived" => true},
             old_value: %{"archived" => false}
           } =
             ChangeCustomField.archive_row(debrief(), true)

    archived = debrief(%{archived_at: ~U[2026-11-01 00:00:00Z]})
    assert %{new_value: %{"archived" => false}} = ChangeCustomField.archive_row(archived, false)
  end

  test "only the team's own fields change, and never a frozen one" do
    team = %Team{id: 1, d4h_permissions: nil, d4h_api_host: "api.ca.d4h.org"}
    assert ChangeCustomField.check(team, debrief()) == :ok

    assert {:error, "Only the organization can change its fields."} =
             ChangeCustomField.check(team, debrief(%{owner_type: "Organisation"}))

    assert {:error, "D4H locks this field. It cannot change."} =
             ChangeCustomField.check(team, debrief(%{frozen: true}))

    assert {:error, "This D4H access key cannot change fields. Use an Owner's key."} =
             ChangeCustomField.check(%{team | d4h_permissions: %{}}, debrief())
  end
end
