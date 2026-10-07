defmodule App.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  # What the app did, for answering questions later: D4H sync runs, rate limits, and
  # security events. Each kind is kept for its own time (App.Model.Event).
  def change do
    create table(:events) do
      add :kind, :string, null: false
      add :team_id, references(:teams, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :nilify_all)
      add :ip, :string
      add :user_agent, :string
      add :duration_ms, :integer
      add :data, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:events, [:kind, :occurred_at])
    create index(:events, [:team_id, :occurred_at])
    create index(:events, [:occurred_at])
  end
end
