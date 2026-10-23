defmodule App.Adapter.D4H.Member do
  alias App.Adapter.D4H.Parse

  # Emergency contacts are maps with string keys, the shape the copy and a change set
  # row hold (#423).
  @contact_fields %{
    "name" => "name",
    "relation" => "relation",
    "primary_phone" => "primaryPhone",
    "secondary_phone" => "secondaryPhone"
  }

  defstruct d4h_member_id: nil,
            d4h_team_id: nil,
            ref_id: nil,
            name: nil,
            position: nil,
            email: nil,
            phone: nil,
            address: nil,
            primary_emergency_contact: nil,
            secondary_emergency_contact: nil,
            joined_at: nil,
            left_at: nil,
            permission: nil,
            status: nil

  def build(record) do
    %__MODULE__{
      d4h_member_id: record["id"],
      d4h_team_id: Parse.team_id(record["owner"]),
      name: record["name"],
      position: record["position"],
      ref_id: record["ref"],
      email: String.downcase(record["email"]["value"] || ""),
      phone: record["mobile"]["phone"],
      address: record["deprecatedAddress"],
      primary_emergency_contact: contact(record["primaryEmergencyContact"]),
      secondary_emergency_contact: contact(record["secondaryEmergencyContact"]),
      joined_at: Parse.optional_datetime(record["startsAt"]),
      left_at: Parse.optional_datetime(record["endsAt"]),
      permission: record["permission"],
      status: record["status"]
    }
  end

  @doc "Each contact field, our name to D4H's."
  def contact_fields, do: @contact_fields

  def empty_contact, do: Map.new(@contact_fields, fn {name, _d4h_name} -> {name, nil} end)

  defp contact(nil), do: empty_contact()

  defp contact(%{} = json),
    do: Map.new(@contact_fields, fn {name, d4h_name} -> {name, blank_to_nil(json[d4h_name])} end)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
