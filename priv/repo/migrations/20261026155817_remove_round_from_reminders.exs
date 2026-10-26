defmodule App.Repo.Migrations.RemoveRoundFromReminders do
  use Ecto.Migration

  # A team admin chooses who gets each reminder (#608), with no cap of 2 per member, so
  # rounds are gone. SQLite drops a column only once no index uses it. Going back adds
  # the column with no rounds in it.
  def change do
    drop unique_index(:reminders, [:activity_id, :member_id, :round])

    alter table(:reminders) do
      remove :round, :integer
    end
  end
end
