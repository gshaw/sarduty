defmodule App.Repo.Migrations.CreateEndorsements do
  use Ecto.Migration

  # Group rule clauses became endorsements, a team-level list that group rules and ID
  # cards share (#320). The clauses moved over in production on 2026-10-13. The move and
  # its plan went with the clause tables in #334, so this now only makes the tables.
  def up do
    create table(:endorsements) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :on_card, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:endorsements, [:team_id, :name])

    create table(:endorsement_qualifications) do
      add :endorsement_id, references(:endorsements, on_delete: :delete_all), null: false
      add :d4h_qualification_id, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:endorsement_qualifications, [:endorsement_id, :d4h_qualification_id])

    create table(:group_endorsements) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :d4h_group_id, :integer, null: false
      add :endorsement_id, references(:endorsements, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:group_endorsements, [:team_id, :d4h_group_id, :endorsement_id])
    create index(:group_endorsements, [:endorsement_id])
  end

  def down do
    drop table(:group_endorsements)
    drop table(:endorsement_qualifications)
    drop table(:endorsements)
  end
end
