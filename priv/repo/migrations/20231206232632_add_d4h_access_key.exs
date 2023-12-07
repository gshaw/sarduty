defmodule App.Repo.Migrations.AddD4HAccessKey do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :d4h_access_key, :binary
    end
  end
end
