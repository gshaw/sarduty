defmodule App.Repo.Migrations.AddFailedAttemptsToUsersTokens do
  use Ecto.Migration

  # Login is by emailed code (#142): a code dies after 5 wrong tries, counted on its
  # token. Links sent before this deploy can't be used, so they go.
  def change do
    execute "DELETE FROM users_tokens WHERE context = 'login'", ""

    alter table(:users_tokens) do
      add :failed_attempts, :integer, null: false, default: 0
    end
  end
end
