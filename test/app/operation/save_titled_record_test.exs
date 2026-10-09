defmodule App.Operation.SaveTitledRecordTest do
  use ExUnit.Case, async: true

  alias App.Model.Group
  alias App.Model.Qualification
  alias App.Operation.SaveTitledRecord

  test "a new qualification or group is a create with its title" do
    assert %{action: :create_qualification, new_value: %{"title" => "Swiftwater"}} =
             SaveTitledRecord.plan(:qualification, nil, "Swiftwater")

    assert %{action: :create_group, new_value: %{"title" => "Rope Team"}} =
             SaveTitledRecord.plan(:group, nil, "Rope Team")
  end

  test "a rename names the record's Records id and its old title" do
    row = SaveTitledRecord.plan(:group, %Group{d4h_group_id: 9, title: "Rope"}, "Rope Team")
    assert row.action == :update_group
    assert row.d4h_record_id == 9
    assert row.old_value == %{"title" => "Rope"}

    row =
      SaveTitledRecord.plan(
        :qualification,
        %Qualification{d4h_qualification_id: 4, title: "SFA"},
        "First Aid"
      )

    assert row.action == :update_qualification
    assert row.d4h_record_id == 4
  end
end
