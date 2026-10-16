defmodule App.Operation.ChangeActivityTagsTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.ChangeSetRow
  alias App.Operation.ChangeActivityTags

  @activity %Activity{d4h_activity_id: 900, activity_kind: "exercise"}
  @titles %{1 => "Primary Hours", 2 => "Flat Water", 3 => "Rope"}

  test "the same tags in any order change nothing" do
    assert ChangeActivityTags.plan(@activity, [2, 1], [1, 2, 2], @titles) == :unchanged
  end

  test "the row sends every tag the activity keeps, and names what changed" do
    assert %ChangeSetRow{
             action: :set_activity_tags,
             d4h_record_id: 900,
             old_value: %{"kind" => "exercise", "tag_ids" => [1, 2]},
             new_value: %{
               "tag_ids" => [1, 3],
               "titles" => ["Rope"],
               "removed_titles" => ["Flat Water"]
             }
           } = ChangeActivityTags.plan(@activity, [2, 1], [3, 1], @titles)
  end

  test "a tag the refresh hasn't copied is named by its id" do
    row = ChangeActivityTags.plan(@activity, [], [77], @titles)
    assert row.new_value["titles"] == ["Tag 77"]
  end
end
