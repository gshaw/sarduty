defmodule App.Repo.Migrations.AddActivitiesTeamStartedIndex do
  use Ecto.Migration

  # A team's activities newest first, and a year as a range of start times: Activities
  # and every report on activities read them this way (#784).
  def change do
    create index(:activities, [:team_id, :started_at])
  end
end
