defmodule App.Repo.Migrations.CreateReports do
  use Ecto.Migration

  # A team's own reports (#768): a query in the report language, run on the team's
  # records every time it opens, never its rows. Any team admin runs, changes, or deletes
  # one. `values` are the picked values saved with it; `agent` names the agent that wrote
  # it, when one did.
  def change do
    create table(:reports) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :about, :string
      add :query, :text, null: false
      add :values, :map, null: false, default: %{}
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
      add :agent, :string
      timestamps(type: :utc_datetime)
    end

    create index(:reports, [:team_id])
    create index(:reports, [:created_by_user_id])
  end
end
