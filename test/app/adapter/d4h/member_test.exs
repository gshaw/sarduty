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

  # D4H keeps both as the day at 00:00 UTC (#1058).
  test "the join and leave dates are D4H's days, not the evening before" do
    member =
      %{"startsAt" => "2018-04-28T00:00:00.000Z", "endsAt" => "2026-11-12T00:00:00.000Z"}
      |> record()
      |> D4H.Member.build()

    assert member.joined_on == ~D[2018-04-28]
    assert member.left_on == ~D[2026-11-12]
  end

  test "a member with no contacts in the JSON has empty ones" do
    member = %{} |> record() |> D4H.Member.build()
    assert member.primary_emergency_contact == D4H.Member.empty_contact()
  end
end
