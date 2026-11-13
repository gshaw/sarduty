defmodule App.Operation.SaveOwnDetailsTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.SaveOwnDetails

  defp contact(name, phone),
    do: %{
      "name" => name,
      "relation" => "Partner",
      "primary_phone" => phone,
      "secondary_phone" => nil
    }

  defp details do
    %Member{
      address: "1 Main St",
      primary_emergency_contact: contact("Sam", "604-555-0100"),
      secondary_emergency_contact: D4H.Member.empty_contact()
    }
  end

  defp values(overrides \\ %{}) do
    Map.merge(
      %{
        "address" => "1 Main St",
        "primary_emergency_contact" => contact("Sam", "604-555-0100"),
        "secondary_emergency_contact" => D4H.Member.empty_contact()
      },
      overrides
    )
  end

  test "the same values change nothing" do
    assert SaveOwnDetails.plan(details(), values()) == :unchanged
  end

  test "names only what changed, with the copy's old value" do
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

  test "a contact the sync has not copied yet counts as empty" do
    member = %Member{details() | secondary_emergency_contact: nil}

    assert SaveOwnDetails.plan(member, values()) == :unchanged
  end

  test "blank fields are nil, so clearing the address is a change and blanks are not" do
    second = Map.new(D4H.Member.empty_contact(), fn {key, _nil} -> {key, ""} end)

    assert SaveOwnDetails.plan(details(), values(%{"secondary_emergency_contact" => second})) ==
             :unchanged

    assert %{new_value: %{"address" => nil}} =
             SaveOwnDetails.plan(details(), values(%{"address" => ""}))
  end

  describe "member fields" do
    alias App.Model.CustomField

    defp field(id, type \\ "text"),
      do: %CustomField{d4h_custom_field_id: id, field_type: type, member_privacy: "editable"}

    defp with_values(values), do: %Member{details() | custom_values: values}

    test "a changed field goes on the same row as the details, with its old value" do
      form = values(%{"address" => "2 Oak Ave", "fields" => %{"630" => "SF 7"}})
      plan = %{"630" => "SF 12"} |> with_values() |> SaveOwnDetails.plan(form, [field(630)])

      assert plan == %{
               old_value: %{"address" => "1 Main St", "custom_values" => %{"630" => "SF 12"}},
               new_value: %{"address" => "2 Oak Ave", "custom_values" => %{"630" => "SF 7"}}
             }
    end

    test "only the fields given go, and only the ones that changed" do
      form = values(%{"fields" => %{"630" => "SF 12", "700" => ["2"], "855" => "1990"}})
      fields = [field(630), field(700, "multiple_choice")]

      plan =
        %{"630" => "SF 12", "700" => [1]} |> with_values() |> SaveOwnDetails.plan(form, fields)

      assert plan == %{
               old_value: %{"custom_values" => %{"700" => [1]}},
               new_value: %{"custom_values" => %{"700" => [2]}}
             }
    end

    test "a field id the member may not change is never sent" do
      form = values(%{"fields" => %{"855" => "1990"}})
      assert SaveOwnDetails.plan(details(), form, [field(630)]) == :unchanged
    end

    test "clearing a field sends nil" do
      form = values(%{"fields" => %{"630" => " "}})
      plan = %{"630" => "SF 12"} |> with_values() |> SaveOwnDetails.plan(form, [field(630)])
      assert %{new_value: %{"custom_values" => %{"630" => nil}}} = plan
    end
  end
end
