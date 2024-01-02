defmodule App.Repo.Migrations.AddD4HAPIHost do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :d4h_access_key, :binary
      add :d4h_access_key, :string
      add :d4h_api_host, :string
      add :d4h_changed_at, :utc_datetime
    end
  end
end
