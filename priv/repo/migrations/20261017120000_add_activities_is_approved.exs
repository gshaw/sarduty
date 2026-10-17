defmodule App.Repo.Migrations.AddActivitiesIsApproved do
  use Ecto.Migration

  # D4H's read-only `approved` flag (#356). An approved activity refuses every change, and
  # only D4H can reopen it. The next refresh fills it in.
  def change do
    alter table(:activities) do
      add :is_approved, :boolean, null: false, default: false
    end
  end
end
