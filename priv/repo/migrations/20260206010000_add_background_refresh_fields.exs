defmodule App.Repo.Migrations.AddBackgroundRefreshFields do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :d4h_access_key, :binary
      add :d4h_refresh_result, :string
    end

    alter table(:users) do
      add :is_admin, :boolean, default: false, null: false
    end
  end
end
