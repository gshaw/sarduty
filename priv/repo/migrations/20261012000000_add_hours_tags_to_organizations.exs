defmodule App.Repo.Migrations.AddHoursTagsToOrganizations do
  use Ecto.Migration

  # The D4H tags that count as primary and secondary hours on a tax credit letter (#289).
  # Blank keeps "Primary Hours" and "Secondary Hours".
  def change do
    alter table(:organizations) do
      add :primary_hours_tag, :string
      add :secondary_hours_tag, :string
    end
  end
end
