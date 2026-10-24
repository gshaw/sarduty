defmodule App.Repo.Migrations.IndexHeldEquipment do
  use Ecto.Migration

  # EquipmentItem.held_by/2 (#490) finds a member's items, then what's inside each one,
  # on every member tab.
  def change do
    create index(:equipment_items, [:team_id, :member_id])
    create index(:equipment_items, [:team_id, :d4h_container_id])
  end
end
