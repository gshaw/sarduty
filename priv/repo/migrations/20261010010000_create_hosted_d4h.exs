defmodule App.Repo.Migrations.CreateHostedD4H do
  use Ecto.Migration

  # SAR Duty's own D4H-compatible store, for teams without D4H (docs/hosted-d4h.md).
  # These tables are the system of record for those teams. The sync copies them into
  # members, activities, and the rest exactly as it copies D4H, so ids here are the
  # teams' "D4H ids". Activities of all three kinds share one id space, as in D4H.
  def change do
    create table(:hosted_teams) do
      add :title, :string, null: false
      add :subdomain, :string, null: false
      add :timezone, :string, null: false
      add :lat, :float
      add :lng, :float
      # SHA-256 of the bearer token. The token itself is the team's encrypted D4H key.
      add :access_key_hash, :binary, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:hosted_teams, [:subdomain])
    create unique_index(:hosted_teams, [:access_key_hash])

    create table(:hosted_members) do
      add :hosted_team_id, references(:hosted_teams, on_delete: :delete_all), null: false
      add :ref, :string
      add :name, :string, null: false
      add :position, :string
      add :email, :string
      add :phone, :string
      add :address, :string
      add :status, :string, null: false
      add :permission, :integer, null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime
      timestamps(type: :utc_datetime_usec)
    end

    create index(:hosted_members, [:hosted_team_id, :updated_at])

    create table(:hosted_tags) do
      add :hosted_team_id, references(:hosted_teams, on_delete: :delete_all), null: false
      add :title, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:hosted_tags, [:hosted_team_id])

    create table(:hosted_activities) do
      add :hosted_team_id, references(:hosted_teams, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :reference, :string
      add :title, :string
      add :description, :text
      add :tracking_number, :string
      add :published, :boolean, null: false, default: false
      add :street, :string
      add :town, :string
      add :region, :string
      add :country, :string
      add :lat, :float
      add :lng, :float
      add :tag_ids, {:array, :integer}, null: false, default: []
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :deleted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:hosted_activities, [:hosted_team_id, :kind, :updated_at])

    create table(:hosted_attendances) do
      add :hosted_team_id, references(:hosted_teams, on_delete: :delete_all), null: false
      add :activity_id, references(:hosted_activities, on_delete: :delete_all), null: false
      add :member_id, references(:hosted_members, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:hosted_attendances, [:hosted_team_id, :updated_at])
    create index(:hosted_attendances, [:activity_id])

    create table(:hosted_qualifications) do
      add :hosted_team_id, references(:hosted_teams, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :expires_months_default, :integer
      timestamps(type: :utc_datetime_usec)
    end

    create index(:hosted_qualifications, [:hosted_team_id])

    create table(:hosted_qualification_awards) do
      add :hosted_team_id, references(:hosted_teams, on_delete: :delete_all), null: false
      add :member_id, references(:hosted_members, on_delete: :delete_all), null: false

      add :qualification_id, references(:hosted_qualifications, on_delete: :delete_all),
        null: false

      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime
      timestamps(type: :utc_datetime_usec)
    end

    create index(:hosted_qualification_awards, [:hosted_team_id])

    create table(:hosted_groups) do
      add :hosted_team_id, references(:hosted_teams, on_delete: :delete_all), null: false
      add :title, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:hosted_groups, [:hosted_team_id])

    create table(:hosted_group_memberships) do
      add :hosted_team_id, references(:hosted_teams, on_delete: :delete_all), null: false
      add :group_id, references(:hosted_groups, on_delete: :delete_all), null: false
      add :member_id, references(:hosted_members, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:hosted_group_memberships, [:group_id, :member_id])
    create index(:hosted_group_memberships, [:hosted_team_id])
  end
end
