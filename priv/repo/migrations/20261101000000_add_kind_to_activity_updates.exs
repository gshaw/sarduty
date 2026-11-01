defmodule App.Repo.Migrations.AddKindToActivityUpdates do
  use Ecto.Migration

  # An update is a team admin's news, or the message to a signed up member they took off
  # the activity (#704), which ends differently and goes even after the start.
  def change do
    alter table(:activity_updates) do
      add :kind, :string, null: false, default: "update"
    end
  end
end
