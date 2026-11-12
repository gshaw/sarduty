defmodule App.Repo.Migrations.AddCustomFieldDetails do
  use Ecto.Migration

  # The rest of what D4H says about a custom field (#872): its resource bundle, a named
  # group of one kind's fields, and when it was added, whether it's searchable, and
  # whether it's frozen. Options keep their owner in the `options` maps, so they need no
  # column. The next refresh fills them in.
  def change do
    create table(:custom_field_bundles) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :d4h_bundle_id, :integer, null: false
      add :title, :string, null: false
      add :target, :string, null: false
      add :ordering, :integer, null: false, default: 0
      add :owner_type, :string
      add :owner_id, :integer
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:custom_field_bundles, [:team_id, :d4h_bundle_id])

    alter table(:custom_fields) do
      add :bundle_id, references(:custom_field_bundles, on_delete: :nilify_all)
      add :d4h_created_at, :utc_datetime
      add :searchable, :boolean, null: false, default: false
      add :frozen, :boolean, null: false, default: false
    end

    create index(:custom_fields, [:bundle_id])
  end
end
