defmodule App.Repo.Migrations.RemoveUsersTeamIdAndD4HAccessKey do
  use Ecto.Migration

  # Access comes from D4H managers and keys are per team (#57), so a user's old team and
  # personal D4H key are unused. `down` brings the columns back empty.
  def up do
    alter table(:users) do
      remove :team_id
      remove :d4h_access_key
    end
  end

  def down do
    alter table(:users) do
      add :team_id, references(:teams)
      add :d4h_access_key, :string
    end
  end
end
