defmodule App.ViewData.ChangeHistoryTest do
  use ExUnit.Case, async: true

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

  test "D4H access changes use D4H's names" do
    assert describe_change(%{
             record_kind: :member,
             action: :changed,
             fields: ["d4h_permission"],
             old_value: %{"d4h_permission" => 1},
             new_value: %{"d4h_permission" => 2}
           }) == "D4H access changed from Editor to Member"
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
           ) == "Deleted in D4H"
  end
end
