defmodule App.Operation.SaveOwnDetailsTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.MemberDetails
  alias App.Operation.SaveOwnDetails

  defp contact(name, phone),
    do: %{
      "name" => name,
      "relation" => "Partner",
      "primary_phone" => phone,
      "secondary_phone" => nil
    }

  defp details do
    %MemberDetails{
      address: "1 Main St",
      primary_emergency_contact: contact("Sam", "604-555-0100"),
      secondary_emergency_contact: MemberDetails.empty_contact()
    }
  end

  defp values(overrides \\ %{}) do
    Map.merge(
      %{
        "address" => "1 Main St",
        "primary_emergency_contact" => contact("Sam", "604-555-0100"),
        "secondary_emergency_contact" => MemberDetails.empty_contact()
      },
      overrides
    )
  end

  test "the same values change nothing" do
    assert SaveOwnDetails.plan(details(), values()) == :unchanged
  end

  test "names only what changed, with D4H's old value" do
    plan = SaveOwnDetails.plan(details(), values(%{"address" => "2 Oak Ave"}))

    assert plan == %{
             old_value: %{"address" => "1 Main St"},
             new_value: %{"address" => "2 Oak Ave"}
           }
  end

  test "a contact goes whole when one of its fields changed" do
    changed = contact("Sam", "604-555-0199")
    plan = SaveOwnDetails.plan(details(), values(%{"primary_emergency_contact" => changed}))

    assert plan.new_value == %{"primary_emergency_contact" => changed}
    assert plan.old_value == %{"primary_emergency_contact" => contact("Sam", "604-555-0100")}
  end

  test "blank fields are nil, so clearing the address is a change and blanks are not" do
    second = Map.new(MemberDetails.empty_contact(), fn {key, _nil} -> {key, ""} end)

    assert SaveOwnDetails.plan(details(), values(%{"secondary_emergency_contact" => second})) ==
             :unchanged

    assert %{new_value: %{"address" => nil}} =
             SaveOwnDetails.plan(details(), values(%{"address" => ""}))
  end
end
