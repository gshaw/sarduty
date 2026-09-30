defmodule App.Repo.Migrations.AddOnCardToGroupRuleClauses do
  use Ecto.Migration

  def change do
    alter table(:group_rule_clauses) do
      add :on_card, :boolean, null: false, default: false
    end
  end
end
