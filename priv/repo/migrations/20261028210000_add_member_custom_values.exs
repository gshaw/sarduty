defmodule App.Repo.Migrations.AddMemberCustomValues do
  use Ecto.Migration

  # Member custom fields a team admin picks to copy (#681), none at first, and the
  # members' values for those fields. Nil until copied, so the first copy is the baseline.
  def change do
    alter table(:custom_fields) do
      add :copy_values, :boolean, null: false, default: false
    end

    alter table(:members) do
      add :custom_values, :map
    end
  end
end
