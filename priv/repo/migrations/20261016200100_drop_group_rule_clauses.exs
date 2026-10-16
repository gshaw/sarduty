defmodule App.Repo.Migrations.DropGroupRuleClauses do
  use Ecto.Migration

  # Endorsements replaced these in #320, and they were kept one release.
  def up do
    drop table(:group_rule_clause_qualifications)
    drop table(:group_rule_clauses)
  end

  def down do
    create table(:group_rule_clauses) do
      add :team_id, references(:teams), null: false
      add :d4h_group_id, :integer, null: false
      add :name, :string
      add :on_card, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:group_rule_clauses, [:team_id, :d4h_group_id])

    create table(:group_rule_clause_qualifications) do
      add :group_rule_clause_id, references(:group_rule_clauses, on_delete: :delete_all),
        null: false

      add :d4h_qualification_id, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:group_rule_clause_qualifications, [
             :group_rule_clause_id,
             :d4h_qualification_id
           ])
  end
end
