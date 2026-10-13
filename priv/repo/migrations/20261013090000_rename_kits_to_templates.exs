defmodule App.Repo.Migrations.RenameKitsToTemplates do
  use Ecto.Migration

  # Kits became templates (#162): they hold tags and groups to invite now, not just
  # equipment. SQLite keeps an index's name through a rename, so each is made again.
  @children [
    {:kit_items, :template_items, [:equipment_item_id]},
    {:kit_tags, :template_tags, [:tag_id]},
    {:kit_groups, :template_groups, [:group_id]}
  ]

  def up do
    drop index(:kits, [:team_id])
    rename table(:kits), to: table(:templates)
    create index(:templates, [:team_id])

    for {old, new, [other]} <- @children do
      drop unique_index(old, [:kit_id, other])
      if other != :equipment_item_id, do: drop(index(old, [other]))
      rename table(old), to: table(new)
      rename table(new), :kit_id, to: :template_id
      create unique_index(new, [:template_id, other])
      if other != :equipment_item_id, do: create(index(new, [other]))
    end

    execute "UPDATE change_sets SET source = 'template' WHERE source = 'kit'"
  end

  def down do
    execute "UPDATE change_sets SET source = 'kit' WHERE source = 'template'"

    for {old, new, [other]} <- @children do
      drop unique_index(new, [:template_id, other])
      if other != :equipment_item_id, do: drop(index(new, [other]))
      rename table(new), :template_id, to: :kit_id
      rename table(new), to: table(old)
      create unique_index(old, [:kit_id, other])
      if other != :equipment_item_id, do: create(index(old, [other]))
    end

    drop index(:templates, [:team_id])
    rename table(:templates), to: table(:kits)
    create index(:kits, [:team_id])
  end
end
