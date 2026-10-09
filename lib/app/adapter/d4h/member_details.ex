defmodule App.Adapter.D4H.MemberDetails do
  # A member's contact details that SAR Duty doesn't copy: read fresh for the member's
  # own details page (#156), never stored. Contacts are maps with string keys, the
  # shape a change set row holds: "name", "relation", "primary_phone", "secondary_phone".

  defstruct address: nil, primary_emergency_contact: nil, secondary_emergency_contact: nil

  @contact_fields %{
    "name" => "name",
    "relation" => "relation",
    "primary_phone" => "primaryPhone",
    "secondary_phone" => "secondaryPhone"
  }

  def contact_fields, do: @contact_fields

  def build(record) do
    %__MODULE__{
      address: record["deprecatedAddress"],
      primary_emergency_contact: contact(record["primaryEmergencyContact"]),
      secondary_emergency_contact: contact(record["secondaryEmergencyContact"])
    }
  end

  defp contact(nil), do: empty_contact()

  defp contact(%{} = json),
    do: Map.new(@contact_fields, fn {name, d4h_name} -> {name, blank_to_nil(json[d4h_name])} end)

  def empty_contact, do: Map.new(@contact_fields, fn {name, _d4h_name} -> {name, nil} end)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
