defmodule App.Repo.Migrations.AddMessageToReminders do
  use Ecto.Migration

  # A team admin's own words at the top of a reminder email (#609), the same on each row
  # of one send. The job reads it from the row, since its args are ids only.
  def change do
    alter table(:reminders) do
      add :message, :text
    end
  end
end
