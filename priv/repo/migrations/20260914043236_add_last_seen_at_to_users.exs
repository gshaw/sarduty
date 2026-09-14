defmodule App.Repo.Migrations.AddLastSeenAtToUsers do
  use Ecto.Migration

  # Additive only: the previous release ignores a column it doesn't know, so going back
  # to it needs no down migration. Ecto wraps up/0 in a transaction, so a failed
  # backfill also undoes the column.
  def up do
    alter table(:users) do
      add :last_seen_at, :utc_datetime
    end

    flush()

    # Start from each user's newest login, so /admin has history on the first day. Admins
    # are skipped, as RecordUserSeen skips them. Tokens are UTC without a zone; the format
    # matches what Ecto writes for :utc_datetime.
    execute """
    UPDATE users SET last_seen_at = (
      SELECT strftime('%Y-%m-%dT%H:%M:%SZ', max(users_tokens.inserted_at))
      FROM users_tokens
      WHERE users_tokens.user_id = users.id AND users_tokens.context = 'session'
    )
    WHERE users.is_admin = 0
    """
  end

  def down do
    alter table(:users) do
      remove :last_seen_at
    end
  end
end
