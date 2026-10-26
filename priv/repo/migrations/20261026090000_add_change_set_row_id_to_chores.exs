defmodule App.Repo.Migrations.AddChangeSetRowIdToChores do
  use Ecto.Migration

  # The agent's proposal a chore came from (#595), so its page can say so.
  def change do
    alter table(:chores) do
      add :change_set_row_id, references(:change_set_rows, on_delete: :nilify_all)
    end
  end
end
