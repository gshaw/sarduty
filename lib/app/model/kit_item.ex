defmodule App.Model.KitItem do
  use App, :model

  alias App.Model.EquipmentItem
  alias App.Model.Kit

  # One item in a kit, with the minutes it adds to an activity's usage. Minutes only
  # count for equipment; D4H takes km for a vehicle and a count for a supply.
  schema "kit_items" do
    belongs_to :kit, Kit
    belongs_to :equipment_item, EquipmentItem
    field :minutes, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end
end
