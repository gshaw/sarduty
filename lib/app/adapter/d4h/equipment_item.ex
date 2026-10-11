defmodule App.Adapter.D4H.EquipmentItem do
  alias App.Adapter.D4H.Parse

  # One D4H equipment item. Its `location` is where it sits: an EquipmentLocation, another
  # Equipment item (a truck, a drawer), or a Member who has it. D4H nests items that way,
  # since `parents` is always empty. `kinds` and `locations` map ids to titles, since
  # the list doesn't always embed them.
  defstruct d4h_equipment_id: nil,
            title: nil,
            item_type: nil,
            kind: nil,
            status: nil,
            barcode: nil,
            serial: nil,
            d4h_location_id: nil,
            location_title: nil,
            d4h_container_id: nil,
            d4h_member_id: nil,
            expires_at: nil

  def build(record, kinds \\ %{}, locations \\ %{}) do
    place = place(record["location"])

    %__MODULE__{
      d4h_equipment_id: record["id"],
      title: blank_to_nil(record["ref"]) || "Item #{record["id"]}",
      item_type: String.downcase(record["type"] || "equipment"),
      kind: kind_title(record["kind"], kinds),
      status: String.downcase(record["status"] || "operational"),
      barcode: blank_to_nil(record["barcode"]),
      serial: blank_to_nil(record["serial"]),
      d4h_location_id: place[:location],
      location_title: place[:location] && Map.get(locations, place[:location]),
      d4h_container_id: place[:container],
      d4h_member_id: place[:member],
      expires_at: Parse.optional_datetime(record["dateExpires"])
    }
  end

  defp place(%{"resourceType" => "EquipmentLocation", "id" => id}) when is_integer(id),
    do: %{location: id}

  defp place(%{"resourceType" => "Equipment", "id" => id}) when is_integer(id),
    do: %{container: id}

  defp place(%{"resourceType" => "Member", "id" => id}) when is_integer(id), do: %{member: id}
  defp place(_none), do: %{}

  defp kind_title(%{"title" => title}, _kinds) when is_binary(title), do: title
  defp kind_title(%{"id" => id}, kinds), do: Map.get(kinds, id)
  defp kind_title(_kind, _kinds), do: nil

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
