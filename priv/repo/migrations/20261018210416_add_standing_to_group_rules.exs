defmodule App.Repo.Migrations.AddStandingToGroupRules do
  use Ecto.Migration

  # cspell:ignore fkey (ecto_sqlite3's suffix for a foreign key's constraint name)

  # "Standing is any of" rules (#366): `group_rules.kind` gains `standing`, and a
  # reference can name a standing. The check now keeps exactly one of endorsement, group,
  # or standing. SQLite can't change a check, so the table is rebuilt.
  def up do
    rebuild(
      ~s|"standing" TEXT, CONSTRAINT one_reference CHECK (| <>
        ~s|(endorsement_id IS NOT NULL) + (d4h_group_id IS NOT NULL) + (standing IS NOT NULL) = 1)|,
      "standing"
    )

    create unique_index(:group_rule_references, [:group_rule_id, :standing])
  end

  def down do
    execute "DELETE FROM group_rule_references WHERE standing IS NOT NULL"
    execute "DELETE FROM group_rules WHERE kind = 'standing'"

    rebuild(
      "CONSTRAINT one_reference CHECK ((endorsement_id IS NULL) <> (d4h_group_id IS NULL))",
      nil
    )
  end

  defp rebuild(extra, extra_column) do
    execute """
    CREATE TABLE "group_rule_references_new" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "group_rule_id" INTEGER NOT NULL CONSTRAINT "group_rule_references_group_rule_id_fkey"
        REFERENCES "group_rules"("id") ON DELETE CASCADE,
      "endorsement_id" INTEGER CONSTRAINT "group_rule_references_endorsement_id_fkey"
        REFERENCES "endorsements"("id") ON DELETE CASCADE,
      "d4h_group_id" INTEGER,
      "inserted_at" TEXT NOT NULL,
      "updated_at" TEXT NOT NULL,
      #{extra}
    )
    """

    columns =
      Enum.join(
        ["id", "group_rule_id", "endorsement_id", "d4h_group_id", "inserted_at", "updated_at"] ++
          List.wrap(extra_column),
        ", "
      )

    copied = if extra_column, do: String.replace(columns, ", standing", ", NULL"), else: columns

    execute "INSERT INTO group_rule_references_new (#{columns}) SELECT #{copied} FROM group_rule_references"
    execute "DROP TABLE group_rule_references"
    execute "ALTER TABLE group_rule_references_new RENAME TO group_rule_references"

    create unique_index(:group_rule_references, [:group_rule_id, :endorsement_id])
    create unique_index(:group_rule_references, [:group_rule_id, :d4h_group_id])
    create index(:group_rule_references, [:endorsement_id])
  end
end
