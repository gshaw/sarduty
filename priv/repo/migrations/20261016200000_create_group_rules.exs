defmodule App.Repo.Migrations.CreateGroupRules do
  use Ecto.Migration

  alias App.Operation.PlanGroupRules

  # A group's rules become a list of In and Not in rules over groups and endorsements
  # (#334). Endorsements in a group's rule and the group it started from become In rules.
  # group_endorsements and group_parents stay for one release, so `down` only drops the
  # new tables.
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

    flush()

    for [team_id] <- rows("SELECT id FROM teams", []), do: move_team(team_id)
  end

  def down do
    drop table(:group_rule_references)
    drop table(:group_rules)
  end

  defp move_team(team_id) do
    group_endorsements =
      for [g, e] <-
            rows(
              "SELECT d4h_group_id, endorsement_id FROM group_endorsements
               WHERE team_id = ? ORDER BY id",
              [team_id]
            ),
          do: {g, e}

    parents =
      "SELECT d4h_group_id, parent_d4h_group_id FROM group_parents WHERE team_id = ?"
      |> rows([team_id])
      |> Map.new(fn [g, p] -> {g, p} end)

    group_ids =
      for [g] <- rows("SELECT d4h_group_id FROM groups WHERE team_id = ?", [team_id]), do: g

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    for {g, {kind, id}} <- PlanGroupRules.plan(group_endorsements, parents, group_ids).rules do
      [[rule_id]] =
        rows(
          "INSERT INTO group_rules (team_id, d4h_group_id, kind, inserted_at, updated_at)
           VALUES (?, ?, 'in', ?, ?) RETURNING id",
          [team_id, g, now, now]
        )

      column = if kind == :group, do: "d4h_group_id", else: "endorsement_id"

      rows(
        "INSERT INTO group_rule_references (group_rule_id, #{column}, inserted_at, updated_at)
         VALUES (?, ?, ?, ?)",
        [rule_id, id, now, now]
      )
    end
  end

  defp rows(sql, params), do: repo().query!(sql, params).rows
end
