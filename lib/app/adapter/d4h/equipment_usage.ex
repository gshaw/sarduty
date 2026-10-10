defmodule App.Adapter.D4H.EquipmentUsage do
  alias App.Adapter.D4H.Parse

  # An item used on an activity. D4H fills one of `duration` (minutes, for equipment),
  # `distance` (km, for a vehicle), or `used` (a count, for a supply).
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
      distance: record["distance"],
      used: record["used"]
    }
  end
end
