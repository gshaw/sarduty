defmodule App.Repo.Migrations.AddEquipmentItemToD4HChanges do
  use Ecto.Migration

  # An equipment item's History tab (#1014): what the refresh saw change on an item in
  # D4H. The refresh deletes an item D4H stops listing, and its page with it, so its
  # history goes too.
  def change do
    alter table(:d4h_changes) do
      add :equipment_item_id, references(:equipment_items, on_delete: :delete_all)
    end

    create index(:d4h_changes, [:team_id, :equipment_item_id, :seen_at])
  end
end
