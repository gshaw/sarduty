defmodule App.Repo.Migrations.CreateGroupRules do
  use Ecto.Migration

  # A group's rules became a list of In and Not in rules over groups and endorsements
  # (#334). Endorsements in a group's rule and the group it started from moved over as In
  # rules in production on 2026-10-16. The move and its plan went with the old tables in
  # #336, so this now only makes the tables.
  def up do
    create table(:group_rules) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :d4h_group_id, :integer, null: false
      add :kind, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:group_rules, [:team_id, :d4h_group_id])

    # Exactly one of endorsement_id and d4h_group_id is set. A group is by D4H id, not a
    # foreign key: the sync deletes a group's row when D4H drops it, and the rule must
    # then break rather than vanish or block the sync.
    create table(:group_rule_references) do
      add :group_rule_id, references(:group_rules, on_delete: :delete_all), null: false
      add :endorsement_id, references(:endorsements, on_delete: :delete_all)

      add :d4h_group_id, :integer,
        check: %{
          name: "one_reference",
          expr: "(endorsement_id IS NULL) <> (d4h_group_id IS NULL)"
        }

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:group_rule_references, [:group_rule_id, :endorsement_id])
    create unique_index(:group_rule_references, [:group_rule_id, :d4h_group_id])
    create index(:group_rule_references, [:endorsement_id])
  end

  def down do
    drop table(:group_rule_references)
    drop table(:group_rules)
  end
end
