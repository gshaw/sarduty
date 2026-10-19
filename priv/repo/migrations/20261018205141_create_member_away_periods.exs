defmodule App.Repo.Migrations.CreateMemberAwayPeriods do
  use Ecto.Migration

  # Member standing (#366): SAR Duty's own data, never sent to D4H. Dates are days on the
  # team's clock, and standing is worked out from them when read, so no job flips it.
  def change do
    create table(:member_away_periods) do
      add :team_id, references(:teams), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
      add :reason, :string, null: false
      add :created_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:member_away_periods, [:team_id, :member_id])

    # What a team admin changed in a member's standing, for the member's history. Away
    # periods can be deleted, so the log keeps its own copy of the dates and reason.
    create table(:member_standing_changes) do
      add :team_id, references(:teams), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :details, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:member_standing_changes, [:team_id, :member_id, :inserted_at])
  end
end
