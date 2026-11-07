defmodule App.Adapter.D4H.EquipmentItem do
  alias App.Adapter.D4H.Parse

  # One D4H equipment item. Its `location` is where it sits: an EquipmentLocation, another
  # Equipment item (a truck, a drawer), or a Member who has it. D4H nests items that way,
  # since `parents` is always empty. `kinds` maps ids to kinds and `locations` ids to
  # titles, since the list doesn't always embed them. D4H's costs are whole cents, and an
  # item's blank cost is its kind's (#950): South Fraser's vehicles cost 67 per km, EMCR's
  # $0.67, checked live 2026-11-07.
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
            expires_at: nil,
            custom_values: %{},
            cost_per_km_cents: nil,
            cost_per_hour_cents: nil,
            cost_per_use_cents: nil

  def build(record, kinds \\ %{}, locations \\ %{}) do
    %__MODULE__{
      d4h_equipment_id: record["id"],
      title: title(record),
      item_type: String.downcase(record["type"] || "equipment"),
      status: String.downcase(record["status"] || "operational"),
      barcode: blank_to_nil(record["barcode"]),
      serial: blank_to_nil(record["serial"]),
      expires_at: Parse.optional_datetime(record["dateExpires"]),
      custom_values: Parse.custom_values(record["customFieldValues"])
    }
    |> struct!(place_fields(place(record["location"]), locations))
    |> struct!(kind_and_costs(record, kind(record["kind"], kinds)))
  end

  defp place_fields(place, locations) do
    [
      d4h_location_id: place[:location],
      location_title: place[:location] && Map.get(locations, place[:location]),
      d4h_container_id: place[:container],
      d4h_member_id: place[:member]
    ]
  end

  @doc "A kind from D4H's list, as `build/3` reads it from `kinds`."
  def build_kind(record),
    do: {record["id"], Map.take(record, ~w(title costPerDistance costPerHour costPerUse))}

  defp title(record), do: blank_to_nil(record["ref"]) || "Item #{record["id"]}"

  defp place(%{"resourceType" => "EquipmentLocation", "id" => id}) when is_integer(id),
    do: %{location: id}

  defp place(%{"resourceType" => "Equipment", "id" => id}) when is_integer(id),
    do: %{container: id}

  defp place(%{"resourceType" => "Member", "id" => id}) when is_integer(id), do: %{member: id}
  defp place(_none), do: %{}

  # The item embeds its kind, with or without its title and costs; the list fills in
  # what it leaves out.
  defp kind(%{"id" => id} = kind, kinds),
    do: kinds |> Map.get(id, %{}) |> Map.merge(drop_nils(kind))

  defp kind(_kind, _kinds), do: %{}

  defp drop_nils(map), do: map |> Enum.reject(&is_nil(elem(&1, 1))) |> Map.new()

  defp kind_and_costs(record, kind) do
    [
      kind: kind["title"],
      cost_per_km_cents: cost(record, kind, "costPerDistance"),
      cost_per_hour_cents: cost(record, kind, "costPerHour"),
      cost_per_use_cents: cost(record, kind, "costPerUse")
    ]
  end

  defp cost(record, kind, key) do
    case record[key] do
      cents when is_integer(cents) -> cents
      _blank -> if is_integer(kind[key]), do: kind[key]
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
