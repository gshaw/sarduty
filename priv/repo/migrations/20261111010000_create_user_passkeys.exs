defmodule App.Repo.Migrations.CreateUserPasskeys do
  use Ecto.Migration

  # Passkeys (#129): a second way to log in. One row per passkey a user adds; the private
  # key never leaves their device. Deleting the user deletes their passkeys.
  def change do
    create table(:user_passkeys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :sign_count, :integer, null: false, default: 0
      add :aaguid, :string
      add :name, :string, null: false
      add :added_with, :string
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_passkeys, [:credential_id])
    create index(:user_passkeys, [:user_id])
  end
end
