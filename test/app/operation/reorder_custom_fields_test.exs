defmodule App.Operation.ReorderCustomFieldsTest do
  use ExUnit.Case, async: true

  alias App.Model.CustomField
  alias App.Operation.ReorderCustomFields

  @fields [
    %CustomField{id: 1, d4h_custom_field_id: 91, ordering: 0},
    %CustomField{id: 2, d4h_custom_field_id: 92, ordering: 1},
    %CustomField{id: 3, d4h_custom_field_id: 93, ordering: 2}
  ]

  test "a row for each field that moved, numbered from 0" do
    assert {:ok, rows} = ReorderCustomFields.plan(@fields, ["3", "1", "2"])

    assert Enum.map(rows, &{&1.d4h_record_id, &1.old_value, &1.new_value}) == [
             {93, %{"ordering" => 2}, %{"ordering" => 0}},
             {91, %{"ordering" => 0}, %{"ordering" => 1}},
             {92, %{"ordering" => 1}, %{"ordering" => 2}}
           ]

    assert Enum.all?(rows, &(&1.action == :update_custom_field))

    assert {:ok, [%{d4h_record_id: 93}, %{d4h_record_id: 92}]} =
             ReorderCustomFields.plan(@fields, [1, 3, 2])
  end

  test "the same order sends nothing" do
    assert ReorderCustomFields.plan(@fields, [1, 2, 3]) == {:ok, []}
  end

  test "a list that doesn't name each field once is refused" do
    message = {:error, "The fields changed since the page opened. Open it again."}
    assert ReorderCustomFields.plan(@fields, [1, 2]) == message
    assert ReorderCustomFields.plan(@fields, [1, 2, 3, 4]) == message
    assert ReorderCustomFields.plan(@fields, [1, 1, 2]) == message
  end
end
