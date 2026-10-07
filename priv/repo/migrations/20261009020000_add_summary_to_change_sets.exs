defmodule App.Repo.Migrations.AddSummaryToChangeSets do
  use Ecto.Migration

  # An AI agent's change set waits for a team admin (#216). `summary` is the agent's
  # one-line description of it, and `discarded_at` marks one the team admin turned down.
  def change do
    alter table(:change_sets) do
      add :summary, :string
      add :discarded_at, :utc_datetime_usec
    end
  end
end
