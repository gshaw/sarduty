defmodule App.Operation.ApplyTemplateTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.ChangeSetRow
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.Tag
  alias App.Model.Template
  alias App.Model.TemplateGroup
  alias App.Model.TemplateItem
  alias App.Model.TemplateTag
  alias App.Operation.ApplyTemplate

  defp tag(id, title), do: %Tag{id: id, title: title}

  defp item_row(title, status \\ :applied, error \\ nil),
    do: %ChangeSetRow{
      action: :create_equipment_usage,
      status: status,
      error: error,
      new_value: %{"title" => title}
    }

  defp member_row(status \\ :applied),
    do: %ChangeSetRow{action: :create_attendance, status: status}

  describe "adds/3" do
    test "the fields the activity has empty, the items in service, the tags it lacks, and the groups" do
      radio = %EquipmentItem{id: 1, title: "Radio", status: "operational"}
      gone = %EquipmentItem{id: 2, title: "Old radio", status: "retired"}
      cause = %CustomField{d4h_custom_field_id: 7, options: []}
      agency = %CustomField{d4h_custom_field_id: 8, options: []}

      template = %Template{
        template_items: [
          %TemplateItem{equipment_item: radio, minutes: 90},
          %TemplateItem{equipment_item: gone, minutes: 60}
        ],
        template_tags: [
          %TemplateTag{tag: tag(1, "Rope")},
          %TemplateTag{tag: tag(2, "Flat Water")}
        ],
        template_groups: [%TemplateGroup{group: %Group{id: 5, title: "Search Managers"}}],
        custom_values: %{"7" => "Lost", "8" => "RCMP"}
      }

      activity = %Activity{tags: ["Rope"], custom_values: %{"8" => "Surrey RCMP"}}

      assert ApplyTemplate.adds(template, activity, [cause, agency]) == %{
               fills: %{"7" => "Lost"},
               lines: [%{item: radio, minutes: 90, km: nil}],
               tags: [tag(2, "Flat Water")],
               groups: [%Group{id: 5, title: "Search Managers"}]
             }
    end
  end

  describe "numbers/4 (#447)" do
    @now ~U[2026-11-01 12:00:00Z]
    @open %Activity{started_at: ~U[2026-11-07 17:00:00Z], finished_at: ~U[2026-11-07 21:00:00Z]}
    @template %Template{enough_at: 10, full_at: 14}

    test "both from the template, on an open activity with neither" do
      assert ApplyTemplate.numbers(nil, @template, @open, @now) == %{enough_at: 10, full_at: 14}

      assert ApplyTemplate.numbers(nil, %Template{enough_at: 10}, @open, @now) ==
               %{enough_at: 10, full_at: nil}
    end

    test "none on an activity with either number, or once it starts" do
      assert ApplyTemplate.numbers(nil, @template, %{@open | full_at: 8}, @now) == nil
      assert ApplyTemplate.numbers(nil, @template, %{@open | enough_at: 3}, @now) == nil
      assert ApplyTemplate.numbers(nil, @template, @open, @open.started_at) == nil
    end

    test "none from a template without them, and the first template added wins" do
      assert ApplyTemplate.numbers(nil, %Template{}, @open, @now) == nil
      first = %{enough_at: 4, full_at: nil}
      assert ApplyTemplate.numbers(first, @template, @open, @now) == first
    end

    test "numbers_text/1 names the ones it sets" do
      assert ApplyTemplate.numbers_text(%{enough_at: 10, full_at: 14}) ==
               "Enough at 10 and Full at 14"

      assert ApplyTemplate.numbers_text(%{enough_at: nil, full_at: 14}) == "Full at 14"
    end
  end

  test "add_tags/3 adds each tag once, A to Z, leaving out the activity's" do
    picked = [tag(3, "Swiftwater")]
    new = [tag(1, "rope"), tag(3, "Swiftwater"), tag(2, "Flat Water")]

    assert ApplyTemplate.add_tags(picked, new, ["Flat Water"]) == [
             tag(1, "rope"),
             tag(3, "Swiftwater")
           ]

    assert ApplyTemplate.add_tags([], new, nil) == Enum.sort_by(new, &String.downcase(&1.title))
  end

  describe "result/3" do
    test "fields, items, then members, in one line" do
      invited = {:ok, %{rows: [member_row(), member_row()], away: []}, "Oct 26"}

      assert ApplyTemplate.result(2, [item_row("Radio")], invited) ==
               {:info, "2 fields filled in. 1 item added. 2 members added."}
    end

    test "nothing to say when nothing went" do
      assert ApplyTemplate.result(0, [], nil) == {:info, ""}
    end

    test "a refused item or member makes it an error" do
      refused = item_row("Truck", :failed, "Not found.")

      assert ApplyTemplate.result(0, [item_row("Radio"), refused], nil) ==
               {:error, "1 item added. Truck: Not found."}

      invited = {:ok, %{rows: [member_row(:failed)], away: []}, "Oct 26"}
      assert {:error, _text} = ApplyTemplate.result(0, [item_row("Radio")], invited)
    end

    test "a refused invite follows what went" do
      invited = {:error, "Nobody was added. Refused."}

      assert ApplyTemplate.result(1, [item_row("Radio")], invited) ==
               {:error, "1 field filled in. 1 item added. Nobody was added. Refused."}
    end
  end

  test "refused/2 says the fields went, or that nothing did" do
    assert ApplyTemplate.refused(0, "Refused.") == {:error, "Refused."}
    assert ApplyTemplate.refused(2, "Refused.") == {:ok, :error, "2 fields filled in. Refused."}
  end

  describe "invite_text/2" do
    test "everyone on the activity already" do
      assert ApplyTemplate.invite_text(%{rows: [], away: []}, "Oct 26") ==
               "Everyone in those groups is on the activity already."
    end

    test "who was added, then who was away on the day" do
      result = %{rows: [member_row()], away: [:dana, :lee]}

      assert ApplyTemplate.invite_text(result, "Oct 26") ==
               "1 member added. 2 members away on Oct 26 were left out."

      assert ApplyTemplate.invite_text(%{rows: [], away: [:dana]}, "Oct 26") ==
               "Nobody was added. 1 member away on Oct 26 was left out."
    end
  end
end
