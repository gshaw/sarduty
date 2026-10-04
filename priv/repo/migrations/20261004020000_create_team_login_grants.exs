defmodule App.Repo.Migrations.CreateTeamLoginGrants do
  use Ecto.Migration

  # Emails let into a team that D4H doesn't make a manager (#57): a shared role address,
  # or a team whose D4H key fails. Admins add them by hand; /admin lists them.
  def change do
    create table(:team_login_grants) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :reason, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:team_login_grants, [:team_id, :email])
  end
end
