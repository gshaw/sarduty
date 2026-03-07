defmodule App.Repo.Migrations.CreateGroupRuleClauses do
  use Ecto.Migration

  def change do
    create table(:group_rule_clauses) do
      add :team_id, references(:teams), null: false
      add :d4h_group_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:group_rule_clauses, [:team_id, :d4h_group_id])

    create table(:group_rule_clause_qualifications) do
      add :group_rule_clause_id, references(:group_rule_clauses, on_delete: :delete_all),
        null: false

      add :d4h_qualification_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:group_rule_clause_qualifications, [:group_rule_clause_id])

    create unique_index(:group_rule_clause_qualifications, [
      :group_rule_clause_id,
      :d4h_qualification_id
    ])
  end
end
