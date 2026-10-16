defmodule App.Repo.Migrations.AddTeamHoursTags do
  use Ecto.Migration

  # A team names the hours tags its organization leaves blank, and either can name a tag
  # for activities that count for no hours (#323).
  def change do
    alter table(:organizations) do
      add :other_hours_tag, :string
    end

    alter table(:teams) do
      add :primary_hours_tag, :string
      add :secondary_hours_tag, :string
      add :other_hours_tag, :string
    end
  end
end
