defmodule App.Repo.Migrations.AddLogoAtToTeams do
  use Ecto.Migration

  # When the team's saved logo last changed, so its URL can change with it. The next full
  # refresh fills it for a team that has a logo.
  def change do
    alter table(:teams) do
      add :logo_at, :utc_datetime_usec
    end
  end
end
