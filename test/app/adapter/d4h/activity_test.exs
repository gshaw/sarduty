defmodule App.Adapter.D4H.ActivityTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.Activity

  @exercise %{
    "id" => 347_456,
    "resourceType" => "Exercise",
    "owner" => %{"resourceType" => "Team", "id" => 1},
    "reference" => "04638",
    "referenceDescription" => "PLI training",
    "published" => true,
    "approved" => true,
    "startsAt" => "2026-06-14T13:00:00.000Z",
    "endsAt" => "2026-06-14T17:00:00.000Z",
    "address" => %{},
    "tags" => []
  }

  test "reads D4H's approved flag, separate from published (#356)" do
    activity = Activity.build(@exercise)

    assert activity.is_published
    assert activity.is_approved
  end

  test "an activity without the flag, as SAR Duty Records sends, is not approved" do
    refute @exercise |> Map.delete("approved") |> Activity.build() |> Map.fetch!(:is_approved)
  end
end
