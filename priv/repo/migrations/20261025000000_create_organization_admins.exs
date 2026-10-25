defmodule App.Repo.Migrations.CreateOrganizationAdmins do
  use Ecto.Migration

  # Organization admins (#512): emails a SAR Duty admin lets into an organization's
  # space. The email alone logs them in. And each organization's own time zone, for dates
  # about it, set to the zone most of its teams use.
  def up do
    create table(:organization_admins) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :reason, :string
      add :added_by_user_id, references(:users, on_delete: :nilify_all)
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_admins, [:organization_id, :email])
    create index(:organization_admins, [:email])

    alter table(:organizations) do
      add :timezone, :string, null: false, default: "America/Vancouver"
    end

    flush()

    execute("""
    UPDATE organizations SET timezone = COALESCE((
      SELECT t.timezone FROM teams t
      WHERE t.organization_id = organizations.id AND t.timezone IS NOT NULL
      GROUP BY t.timezone ORDER BY count(*) DESC, t.timezone LIMIT 1
    ), 'America/Vancouver')
    """)
  end

  def down do
    alter table(:organizations) do
      remove :timezone
    end

    drop table(:organization_admins)
  end
end
