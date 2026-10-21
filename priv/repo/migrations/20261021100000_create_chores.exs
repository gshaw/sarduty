defmodule App.Repo.Migrations.CreateChores do
  use Ecto.Migration

  # Chores (#341): time a member gives the team outside activities. Each is its own row
  # with its date and minutes, waiting until a team admin accepts or declines it.
  def change do
    create table(:chores) do
      add :team_id, references(:teams), null: false
      add :member_id, references(:members), null: false
      add :chore_category_id, references(:chore_categories), null: false
      add :date, :date, null: false
      add :minutes, :integer, null: false
      add :description, :string, null: false
      add :status, :string, null: false, default: "waiting"
      add :decided_by_user_id, references(:users, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec
      add :decline_reason, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chores, [:team_id, :status])
    create index(:chores, [:member_id, :date])
    create index(:chores, [:chore_category_id])
  end
end
