defmodule App.Adapter.D4H.MemberTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H

  defp record(overrides) do
    Map.merge(
      %{
        "id" => 1,
        "name" => "Jane Doe",
        "owner" => %{"resourceType" => "Team", "id" => 2},
        "email" => %{"value" => "Jane@Example.com"},
        "mobile" => %{"phone" => nil}
      },
      overrides
    )
  end

  test "copies both emergency contacts, with blank fields as nil" do
    member =
      %{
        "primaryEmergencyContact" => %{
          "name" => "Sam Rivera",
          "relation" => "Partner",
          "primaryPhone" => "604-555-0100",
          "secondaryPhone" => ""
        },
        "secondaryEmergencyContact" => nil
      }
      |> record()
      |> D4H.Member.build()

    assert member.primary_emergency_contact == %{
             "name" => "Sam Rivera",
             "relation" => "Partner",
             "primary_phone" => "604-555-0100",
             "secondary_phone" => nil
           }

    assert member.secondary_emergency_contact == D4H.Member.empty_contact()
  end

  test "a member with no contacts in the JSON has empty ones" do
    member = %{} |> record() |> D4H.Member.build()
    assert member.primary_emergency_contact == D4H.Member.empty_contact()
  end
end
