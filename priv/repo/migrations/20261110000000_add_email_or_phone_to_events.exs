defmodule App.Repo.Migrations.AddEmailOrPhoneToEvents do
  use Ecto.Migration

  # The email or number typed, encrypted (App.Field.EncryptedString), beside its `who`
  # hash, so the Events page can show who was tried. Older events keep only the hash.
  def change do
    alter table(:events) do
      add :email_or_phone, :string
    end
  end
end
