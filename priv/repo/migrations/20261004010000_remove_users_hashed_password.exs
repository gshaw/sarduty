defmodule App.Repo.Migrations.RemoveUsersHashedPassword do
  use Ecto.Migration

  # Login is by emailed link (#57), so passwords go. The column was NOT NULL, which users
  # made by a login link can't meet, and SQLite can't relax it in place. `down` brings
  # the column back empty: after a rollback, people reset their password by email.
  def up do
    alter table(:users) do
      remove :hashed_password
    end
  end

  def down do
    alter table(:users) do
      add :hashed_password, :string
    end
  end
end
