defmodule App.Repo.Migrations.AddNameToGroupRuleClauses do
  use Ecto.Migration

  # Additive: the previous release ignores the column, and a clause with no name reads
  # as it did before.
  def change do
    alter table(:group_rule_clauses) do
      add :name, :string
    end
  end
end
