defmodule App.Repo.Migrations.CreateCustomFields do
  use Ecto.Migration

  # D4H's custom fields (#681): the team's own and its organisation's, and their values
  # on activities and equipment, keyed by D4H field id. The next refresh fills them in;
  # nil until then, so history takes that first copy as the baseline, not a change.
  def change do
    create table(:custom_fields) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :d4h_custom_field_id, :integer, null: false
      add :target, :string, null: false
      add :title, :string, null: false
      add :field_type, :string, null: false
      add :required, :boolean, null: false, default: false
      add :restricted, :boolean, null: false, default: false
      add :member_privacy, :string
      add :hint, :text
      add :value_units, :string
      add :ordering, :integer, null: false, default: 0
      add :owner_type, :string
      add :owner_id, :integer
      add :archived_at, :utc_datetime
      add :options, {:array, :map}, null: false, default: []
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:custom_fields, [:team_id, :d4h_custom_field_id])

    alter table(:activities) do
      add :custom_values, :map
    end

    alter table(:equipment_items) do
      add :custom_values, :map
    end
  end
end
