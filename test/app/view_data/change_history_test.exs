defmodule App.ViewData.ChangeHistoryTest do
  use ExUnit.Case, async: true

  alias App.Model.ChangeSetRow
  alias App.Model.D4HChange
  alias App.ViewData.ChangeHistory

  @tz "America/Vancouver"

  defp describe_change(attrs, page \\ :member) do
    D4HChange |> struct(attrs) |> ChangeHistory.describe(page, @tz)
  end

  test "attendance names the activity on a member's page and the member on an activity's" do
    change = %{
      record_kind: :attendance,
      action: :changed,
      fields: ["status"],
      old_value: %{"status" => "absent"},
      new_value: %{"status" => "attending"},
      activity: %{title: "Rope rescue"},
      member: %{name: "Jane Doe"}
    }

    assert describe_change(change, :member) == "Rope rescue attendance changed: attended"
    assert describe_change(change, :activity) == "Jane Doe attendance changed: attended"
  end

  # The same words as a removal in SAR Duty (#704), not as if the activity went.
  test "a row removed in D4H reads Removed from on the member's page" do
    change = %{
      record_kind: :attendance,
      action: :removed,
      activity: %{title: "Rope rescue"},
      member: %{name: "Jane Doe"}
    }

    assert describe_change(change, :member) == "Removed from Rope rescue"
    assert describe_change(change, :activity) == "Jane Doe removed from attendance"
  end

  test "an award shows its expiry in the team's time zone" do
    assert describe_change(%{
             record_kind: :award,
             action: :changed,
             label: "First Aid",
             fields: ["ends_at"],
             new_value: %{"ends_at" => "2026-10-03T03:00:00Z"}
           }) == "First Aid expiry changed. Expires Oct 2, 2026."
  end

  test "contact details are named once, without values" do
    assert describe_change(%{
             record_kind: :member,
             action: :changed,
             fields: ["email", "phone"],
             old_value: %{},
             new_value: %{}
           }) == "Contact details changed"
  end

  test "an emergency contact is named once, without values" do
    assert describe_change(%{
             record_kind: :member,
             action: :changed,
             fields: ["primary_emergency_contact", "secondary_emergency_contact"],
             old_value: %{},
             new_value: %{}
           }) == "Emergency contact changed"
  end

  test "a member's own save says what changed, without values" do
    row = fn new_value ->
      ChangeHistory.describe_row(
        %ChangeSetRow{action: :update_member, new_value: new_value},
        :member
      )
    end

    assert row.(%{"primary_emergency_contact" => %{"name" => "Sam"}}) ==
             "Emergency contact changed in SAR Duty"

    assert row.(%{"address" => "2 Oak Ave", "secondary_emergency_contact" => %{}}) ==
             "Contact details changed in SAR Duty. Emergency contact changed in SAR Duty"

    assert row.(%{"name" => "Jane"}) == "Details changed in SAR Duty"
  end

  test "a deleted group's row names its members and rules (#651)" do
    row = fn old_value ->
      ChangeHistory.describe_row(
        %ChangeSetRow{action: :delete_group, old_value: old_value},
        :member
      )
    end

    assert row.(%{
             "title" => "MIT 2026",
             "members" => ["Alex Rivera", "Bo Tanaka"],
             "rules" => ["In MIT Applicants", "Not in LOA"]
           }) == "Deleted MIT 2026: 2 members; rules: In MIT Applicants, Not in LOA"

    assert row.(%{"title" => "Swiftwater", "members" => [], "rules" => []}) ==
             "Deleted Swiftwater: 0 members"

    assert row.(%{"title" => "Old group"}) == "Deleted Old group"
  end

  # On the member's page it reads as them coming off, not the activity going (#704).
  test "a removed row says who came off what" do
    row = %ChangeSetRow{
      action: :delete_attendance,
      member: %App.Model.Member{name: "Drew Patel"},
      change_set: %App.Model.ChangeSet{activity: %App.Model.Activity{title: "BBQ"}}
    }

    assert ChangeHistory.describe_row(row, :member) == "Removed from BBQ"
    assert ChangeHistory.describe_row(row, :activity) == "Drew Patel removed"
    assert ChangeHistory.source_label(:remove) == "Remove members"
  end

  # Sent before the start, so never "attended" (#444).
  test "a member's reply reads in the reply words" do
    reply = fn status, page ->
      ChangeHistory.describe_row(
        %ChangeSetRow{
          action: :update_attendance,
          new_value: %{"status" => status},
          member: %App.Model.Member{name: "Sam Rivera"},
          change_set: %App.Model.ChangeSet{
            source: :member,
            activity: %App.Model.Activity{title: "Training night"}
          }
        },
        page
      )
    end

    assert reply.("ATTENDING", :activity) == "Sam Rivera signed up"
    assert reply.("ABSENT", :activity) == "Sam Rivera can't make it"
    assert reply.("ATTENDING", :member) == "Signed up for Training night"
    assert reply.("ABSENT", :member) == "Can't make it to Training night"
  end

  test "D4H access changes use D4H's names" do
    assert describe_change(%{
             record_kind: :member,
             action: :changed,
             fields: ["d4h_permission"],
             old_value: %{"d4h_permission" => 1},
             new_value: %{"d4h_permission" => 2}
           }) == "Access changed from Editor to Member"
  end

  test "a deleted group keeps its name" do
    assert describe_change(%{record_kind: :group_membership, action: :removed, label: "Callout"}) ==
             "Removed from the Callout group"
  end

  test "an activity deleted in D4H" do
    assert describe_change(
             %{
               record_kind: :activity,
               action: :changed,
               fields: ["deleted_at"],
               new_value: %{"deleted_at" => "2026-10-03T03:00:00Z"}
             },
             :activity
           ) == "Deleted"
  end

  test "custom field values are named by title (#681)" do
    assert describe_change(
             %{
               record_kind: :activity,
               action: :changed,
               fields: ["custom_values"],
               new_value: %{"custom_values" => %{"Primary Cause" => "Dementia", "Area" => nil}}
             },
             :activity
           ) == "Area cleared. Primary Cause changed to Dementia"
  end

  test "custom fields by title alone, for the MCP (#681)" do
    assert describe_change(
             %{
               record_kind: :activity,
               action: :changed,
               fields: ["custom_values"],
               new_value: %{"custom_values" => ["Primary Cause", "Area"]}
             },
             :activity
           ) == "Area and Primary Cause changed"
  end

  describe "an activity's own saves (#447)" do
    defp activity_row(action, old_value, new_value) do
      ChangeHistory.describe_row(
        %ChangeSetRow{
          action: action,
          old_value: old_value,
          new_value: new_value,
          change_set: %App.Model.ChangeSet{source: :edit}
        },
        :activity,
        @tz
      )
    end

    test "a numbers-only save says from what to what" do
      assert activity_row(:update_activity, %{"enough_at" => 8, "full_at" => nil}, %{
               "enough_at" => 10,
               "full_at" => 14
             }) == "Enough at changed from 8 to 10. Full at set to 14"

      assert activity_row(:update_activity, %{"enough_at" => 8}, %{"enough_at" => nil}) ==
               "Enough at cleared"
    end

    test "a save names each box it changed, in the form's order" do
      old = %{"title" => "Pancake breakfast", "hours" => "primary", "tracking_number" => "26-104"}

      new = %{
        "title" => "Pancake breakfast (Nov)",
        "full_at" => 14,
        "description" => "<p>Bring an apron.</p>",
        "place" => "Hall",
        "location" => "49.1,-123.1",
        "started_at" => "2026-11-07T17:00:00Z",
        "finished_at" => "2026-11-07T21:00:00Z",
        "published" => true,
        "tag_ids" => [2],
        "hours" => "secondary",
        "tracking_number" => "26-105"
      }

      assert activity_row(:update_activity, old, new) ==
               Enum.join(
                 [
                   "Title changed from Pancake breakfast to Pancake breakfast (Nov)",
                   "Start changed to Nov 7, 2026, 10:00",
                   "Finish changed to Nov 7, 2026, 14:00",
                   "Full at set to 14",
                   "Address changed",
                   "Tax credit hours changed from Primary to Secondary",
                   "Tracking number changed from 26-104 to 26-105",
                   "Description changed",
                   "Published"
                 ],
                 ". "
               )
    end

    test "a tracking number set or cleared, and a pin moved alone" do
      assert activity_row(:update_activity, %{"tracking_number" => nil}, %{
               "tracking_number" => "26-105"
             }) == "Tracking number set to 26-105"

      assert activity_row(:update_activity, %{"tracking_number" => "26-105"}, %{
               "tracking_number" => nil
             }) == "Tracking number cleared"

      assert activity_row(:update_activity, %{}, %{"location" => nil}) == "Address changed"
      assert activity_row(:update_activity, %{}, %{"published" => false}) == "No longer published"
    end

    test "a save from before kept no hours choice" do
      assert activity_row(:update_activity, %{"kind" => "exercise"}, %{"tag_ids" => [1]}) ==
               "Tax credit hours changed"
    end

    test "a key no box sends, and Change fields, keep their lines" do
      assert activity_row(:update_activity, %{}, %{"title" => "Nav", "shared" => false}) ==
               "Details changed in SAR Duty"

      assert activity_row(:update_activity, %{}, %{"custom_values" => %{"1" => "x"}}) ==
               "Fields changed in SAR Duty"
    end

    test "a chore send keeps its line: its old value holds only the kind" do
      row = %ChangeSetRow{
        action: :update_activity,
        old_value: %{"kind" => "event"},
        new_value: %{"title" => "Admin chores", "tracking_number" => ""},
        change_set: %App.Model.ChangeSet{source: :chores}
      }

      assert ChangeHistory.describe_row(row, :activity, @tz) == "Details changed in SAR Duty"
    end

    test "an add names the numbers it set" do
      assert activity_row(:create_activity, %{}, %{"title" => "Pancake breakfast"}) ==
               "Added in SAR Duty"

      assert activity_row(:create_activity, %{}, %{
               "title" => "Pancake breakfast",
               "enough_at" => 10
             }) ==
               "Added in SAR Duty. Enough at set to 10"
    end
  end

  test "a finish seen in D4H uses the form's word" do
    assert describe_change(
             %{
               record_kind: :activity,
               action: :changed,
               fields: ["finished_at"],
               new_value: %{"finished_at" => "2026-11-07T21:00:00Z"}
             },
             :activity
           ) == "Finish changed to Nov 7, 2026, 14:00"
  end
end
