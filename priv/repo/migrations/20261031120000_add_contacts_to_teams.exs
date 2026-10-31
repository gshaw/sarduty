defmodule App.Repo.Migrations.AddContactsToTeams do
  use Ecto.Migration

  # Team contacts (#780): the one or two members Get help sends the team's messages to.
  # Nil until a team admin picks them.
  def change do
    alter table(:teams) do
      add :first_contact_id, references(:members, on_delete: :nilify_all)
      add :second_contact_id, references(:members, on_delete: :nilify_all)
    end
  end
end
