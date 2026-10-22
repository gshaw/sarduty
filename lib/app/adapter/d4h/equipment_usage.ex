defmodule App.Adapter.D4H.EquipmentUsage do
  alias App.Adapter.D4H.Parse

  # An item used on an activity. D4H fills one of `duration` (minutes, for equipment),
  # `distance` (for a vehicle), or `used` (a count, for a supply). D4H's spec says
  # `distance` is km, but it holds meters: a 244 km round trip to Squamish came back as
  # 244000. `distance` here is whole km.
  defstruct d4h_equipment_usage_id: nil,
            d4h_activity_id: nil,
            d4h_equipment_id: nil,
            minutes: nil,
            distance: nil,
            used: nil

  def build(record) do
    d4h_activity_id =
      case Parse.activity(record["activity"] || %{}) do
        {:ok, id, _kind} -> id
        {:error, _reason} -> nil
      end

    %__MODULE__{
      d4h_equipment_usage_id: record["id"],
      d4h_activity_id: d4h_activity_id,
      d4h_equipment_id: get_in(record, ["equipment", "id"]),
      minutes: record["duration"],
      distance: km(record["distance"]),
      used: record["used"]
    }
  end

  @doc "D4H's `distance`, meters, as whole km."
  def km(meters) when is_number(meters), do: round(meters / 1000)
  def km(_meters), do: nil

  @doc "Whole km as D4H's `distance`, meters."
  def meters(km), do: km * 1000
end
