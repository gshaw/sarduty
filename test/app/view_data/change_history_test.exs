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
end
