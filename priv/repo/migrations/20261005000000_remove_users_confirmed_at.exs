defmodule App.Repo.Migrations.RemoveUsersConfirmedAt do
  use Ecto.Migration

  # With emailed logins every login proves the address, so confirmed_at means nothing
  # (#141). The confirm and reset_password tokens are left from password login. `down`
  # brings the column back empty; the tokens are gone for good, and nothing reads them.
  def up do
    execute "DELETE FROM users_tokens WHERE context NOT IN ('session', 'login')"

    alter table(:users) do
      remove :confirmed_at
    end
  end

  def down do
    alter table(:users) do
      add :confirmed_at, :naive_datetime
    end
  end
end
