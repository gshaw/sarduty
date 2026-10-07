defmodule App.Repo.Migrations.AddNotAPersonToMembers do
  use Ecto.Migration

  # A team admin marks a D4H member that is a bot or a shared account, so counts and
  # checks leave it out. Set in SAR Duty only; a refresh from D4H never touches it.
  def change do
    alter table(:members) do
      add :not_a_person, :boolean, null: false, default: false
    end
  end
end
