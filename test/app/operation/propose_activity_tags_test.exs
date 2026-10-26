defmodule App.Operation.ProposeActivityTagsTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.Tag
  alias App.Operation.ProposeActivityTags

  @hours_tags %{primary: "Primary Hours", secondary: "Secondary Hours", other: nil}
  @tags [
    %Tag{d4h_tag_id: 1, title: "Primary Hours"},
    %Tag{d4h_tag_id: 2, title: "Secondary Hours"},
    %Tag{d4h_tag_id: 3, title: "Regular Training"}
  ]

  defp activity(id, tags, published \\ false) do
    %Activity{
      id: id,
      d4h_activity_id: 900 + id,
      title: "Activity #{id}",
      activity_kind: "exercise",
      tags: tags,
      is_published: published
    }
  end

  defp plan(activities, requests),
    do:
      activities
      |> Map.new(&{&1.id, &1})
      |> ProposeActivityTags.plan(@tags, @hours_tags, requests)

  test "adds and removes tags by title, sending the whole list D4H keeps" do
    {[row], []} =
      plan([activity(1, ["Regular Training"])], [
        %{
          "activity_id" => 1,
          "add" => ["primary hours"],
          "remove" => ["Regular Training"],
          "reason" => "A course"
        }
      ])

    assert row.action == :set_activity_tags
    assert row.d4h_record_id == 901
    assert row.old_value == %{"kind" => "exercise", "tag_ids" => [3]}
    assert row.new_value["tag_ids"] == [1]
    assert row.new_value["titles"] == ["Primary Hours"]
    assert row.new_value["removed_titles"] == ["Regular Training"]
    assert row.new_value["activity_title"] == "Activity 1"
    assert row.reason == "A course"
  end

  test "a published activity's tags cannot change" do
    {[], [problem]} =
      plan([activity(1, [], true)], [%{"activity_id" => 1, "add" => ["Primary Hours"]}])

    assert problem == "Activity 1 is published. Its tags cannot change."
  end

  test "changes that can't apply come back as problems" do
    activities = [activity(1, ["Primary Hours"]), activity(2, ["Mystery"])]

    {[], problems} =
      plan(activities, [
        %{"activity_id" => 1, "add" => ["Secondary Hours"]},
        %{"activity_id" => 1, "add" => ["Primary Hours"]},
        %{"activity_id" => 2, "add" => ["Primary Hours"]},
        %{"activity_id" => 99, "add" => ["Primary Hours"]},
        %{"activity_id" => 1, "add" => ["Rope"]}
      ])

    assert problems == [
             "Activity 1 would have both hours tags. Remove one.",
             "Activity 1 has those tags already. Nothing to change.",
             "Activity 2 has a tag SAR Duty does not know yet. Try after the next refresh.",
             "No activity 99 on this team, or it is a chore activity.",
             "No tag \"Rope\" on this team, for Activity 1."
           ]
  end
end
