defmodule App.Repo.Migrations.RemoveActivitiesIsApproved do
  use Ecto.Migration

  # D4H's `approved` is true on every published activity, with or without its approval
  # module, so it says nothing `is_published` doesn't (#358).
  def change do
    alter table(:activities) do
      remove :is_approved, :boolean, null: false, default: false
    end
  end
end
