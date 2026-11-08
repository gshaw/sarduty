defmodule App.Repo.Migrations.AddCostsToEquipmentItems do
  use Ecto.Migration

  # D4H's costs on an item, or its kind's when the item has none (#950, step 6), in
  # whole cents as D4H keeps them: per km, per hour, and per use. Nil until the next
  # refresh copies them.
  def change do
    alter table(:equipment_items) do
      add :cost_per_km_cents, :integer
      add :cost_per_hour_cents, :integer
      add :cost_per_use_cents, :integer
    end
  end
end
