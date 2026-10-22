defmodule App.Repo.Migrations.EquipmentUsageDistanceInKm do
  use Ecto.Migration

  # D4H sends a vehicle's distance in meters, and the sync copied it as km: 244,000 km for
  # a trip to Squamish. Usages now hold whole km.
  def up do
    execute "UPDATE equipment_usages SET distance = CAST(ROUND(distance / 1000.0) AS INTEGER) WHERE distance IS NOT NULL"
  end

  def down do
    execute "UPDATE equipment_usages SET distance = distance * 1000 WHERE distance IS NOT NULL"
  end
end
