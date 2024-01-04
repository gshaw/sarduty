defmodule App.Repo.Migrations.AddD4HTeamRefreshedAt do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :d4h_refreshed_at, :utc_datetime
    end
  end
end
