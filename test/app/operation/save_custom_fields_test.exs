defmodule App.Operation.SaveCustomFieldsTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.Member
  alias App.Operation.SaveCustomFields

  @options for id <- 1..8, do: %{"id" => id, "label" => "Option #{id}", "archived" => id == 8}

  @fields [
    %CustomField{d4h_custom_field_id: 420, field_type: "single_choice", options: @options},
    %CustomField{d4h_custom_field_id: 421, field_type: "multiple_choice", options: @options},
    %CustomField{d4h_custom_field_id: 454, field_type: "text"}
  ]

  defp activity(values),
    do: %Activity{id: 5, d4h_activity_id: 50, activity_kind: "incident", custom_values: values}

  test "an untouched form changes no field" do
    activity = activity(%{"420" => [1], "454" => "PROS 1"})

    assert SaveCustomFields.plan(activity, @fields, %{"420" => "1", "454" => "PROS 1"}) ==
             :unchanged
  end

  test "sends only the changed fields, nil to clear one, with their old values" do
    activity = activity(%{"420" => [1], "454" => "PROS 1"})
    params = %{"420" => "2", "421" => ["", "7", "8"], "454" => "  "}

    row = SaveCustomFields.plan(activity, @fields, params)

    assert row.action == :update_activity
    assert row.d4h_record_id == 50
    assert row.new_value == %{"custom_values" => %{"420" => [2], "421" => [7, 8], "454" => nil}}

    assert row.old_value == %{
             "kind" => "incident",
             "custom_values" => %{"420" => [1], "421" => nil, "454" => "PROS 1"}
           }
  end

  test "a field the form didn't send is left alone" do
    row = %{"420" => [1]} |> activity() |> SaveCustomFields.plan(@fields, %{"454" => "x"})
    assert row.new_value == %{"custom_values" => %{"454" => "x"}}
  end

  test "an activity with no values yet takes the filled ones" do
    row = nil |> activity() |> SaveCustomFields.plan(@fields, %{"420" => "1", "454" => ""})
    assert row.new_value == %{"custom_values" => %{"420" => [1]}}
  end

  test "a member's row names the member, and an item's the item" do
    member = %Member{id: 7, d4h_member_id: 70, custom_values: %{}}
    row = SaveCustomFields.plan(member, @fields, %{"454" => "Rescue 3"})

    assert %{action: :update_member, member_id: 7, d4h_record_id: 70} = row
    assert row.new_value == %{"custom_values" => %{"454" => "Rescue 3"}}

    item = %EquipmentItem{id: 9, d4h_equipment_id: 90, custom_values: %{"454" => "A"}}
    row = SaveCustomFields.plan(item, @fields, %{"454" => "B"})

    assert %{action: :update_equipment_item, d4h_record_id: 90} = row
    assert row.old_value == %{"custom_values" => %{"454" => "A"}}
  end

  test "a template fills only the fields the activity has empty" do
    activity = activity(%{"420" => [1], "454" => ""})
    values = %{"420" => [2], "421" => [7], "454" => "PROS", "999" => "Another kind's field"}

    assert SaveCustomFields.fill_empty(%{}, activity, @fields, values) == %{
             "421" => [7],
             "454" => "PROS"
           }
  end

  test "the first template applied wins a field two of them fill" do
    activity = activity(%{})
    fills = SaveCustomFields.fill_empty(%{}, activity, @fields, %{"454" => "First"})

    assert SaveCustomFields.fill_empty(fills, activity, @fields, %{
             "454" => "Second",
             "420" => [3]
           }) ==
             %{"454" => "First", "420" => [3]}

    assert SaveCustomFields.fill_empty(fills, activity, @fields, nil) == fills
  end

  test "a template's archived or deleted options are left out" do
    activity = activity(%{})
    values = %{"420" => [8], "421" => [7, 8, 99]}

    assert SaveCustomFields.fill_empty(%{}, activity, @fields, values) == %{"421" => [7]}
  end
end
