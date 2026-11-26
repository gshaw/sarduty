defmodule App.Repo.Migrations.ChoresLoggedTogether do
  use Ecto.Migration

  # A chore logged for several people at once (#1102): each person's chore shares a
  # logged_together_id, a UUID, and records the member who logged it. Old chores have
  # neither: nobody knows who logged them.
  def change do
    alter table(:chores) do
      add :logged_together_id, :string
      add :logged_by_member_id, references(:members, on_delete: :nilify_all)
    end

    create index(:chores, [:team_id, :logged_together_id])
    create index(:chores, [:logged_by_member_id])
  end
end
