defmodule App.Repo.Migrations.CreateEquipment do
  use Ecto.Migration

  # Equipment (#271): a copy of D4H's items and their usages on activities, and kits,
  # which are SAR Duty's own. A kit is a named set of items with default hours, added
  # to an activity in one step.
  def change do
    create table(:equipment_items) do
      add :team_id, references(:teams), null: false
      add :d4h_equipment_id, :integer, null: false
      add :title, :string, null: false
      add :item_type, :string, null: false
      add :kind, :string
      add :status, :string, null: false
      add :barcode, :string
      add :serial, :string
      add :d4h_location_id, :integer
      add :location_title, :string
      add :d4h_container_id, :integer
      add :member_id, references(:members, on_delete: :nilify_all)
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:equipment_items, [:team_id, :d4h_equipment_id])

    create table(:equipment_usages) do
      add :team_id, references(:teams), null: false
      add :activity_id, references(:activities), null: false
      add :equipment_item_id, references(:equipment_items, on_delete: :delete_all), null: false
      add :d4h_equipment_usage_id, :integer, null: false
      add :minutes, :integer
      add :distance, :integer
      add :used, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:equipment_usages, [:team_id, :d4h_equipment_usage_id])
    create index(:equipment_usages, [:activity_id])
    create index(:equipment_usages, [:equipment_item_id])

    create table(:kits) do
      add :team_id, references(:teams), null: false
      add :title, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:kits, [:team_id])

    create table(:kit_items) do
      add :kit_id, references(:kits, on_delete: :delete_all), null: false
      add :equipment_item_id, references(:equipment_items, on_delete: :delete_all), null: false
      add :minutes, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:kit_items, [:kit_id, :equipment_item_id])
  end
end
