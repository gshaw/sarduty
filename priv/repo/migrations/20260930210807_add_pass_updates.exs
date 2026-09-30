defmodule App.Repo.Migrations.AddPassUpdates do
  use Ecto.Migration

  def change do
    alter table(:member_cards) do
      add :authentication_token, :binary
      add :pass_fingerprint, :string
      add :pass_updated_at, :utc_datetime_usec
    end

    # A phone that added a card's Apple Wallet pass and asked to hear about changes.
    create table(:pass_registrations) do
      add :member_card_id, references(:member_cards, on_delete: :delete_all), null: false
      add :device_library_identifier, :string, null: false
      add :push_token, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:pass_registrations, [:member_card_id, :device_library_identifier])
    create index(:pass_registrations, [:device_library_identifier])
  end
end
