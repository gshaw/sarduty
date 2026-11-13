defmodule App.Repo.Migrations.KeepEveryMemberField do
  use Ecto.Migration

  # SAR Duty keeps every member field's values (#1056), so the Copy box goes. Each
  # member's values are cleared, so the next read is a baseline and history doesn't say
  # every newly kept field changed. Forgetting the members list head makes the next sync,
  # within 10 minutes, read the members whole rather than wait for the night's refresh.
  def up do
    alter table(:custom_fields) do
      remove :copy_values
    end

    execute "UPDATE members SET custom_values = NULL"

    execute """
    UPDATE teams
    SET d4h_sync_state = json_remove(d4h_sync_state, '$.heads.members')
    WHERE json_valid(d4h_sync_state)
    """
  end

  # Nothing is copied again until a team admin picks its member fields, as before, and
  # the values go so the old copy's next read is a baseline too.
  def down do
    alter table(:custom_fields) do
      add :copy_values, :boolean, null: false, default: false
    end

    execute "UPDATE members SET custom_values = NULL"
  end
end
