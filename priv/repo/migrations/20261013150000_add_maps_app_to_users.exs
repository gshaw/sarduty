defmodule App.Repo.Migrations.AddMapsAppToUsers do
  use Ecto.Migration

  # The maps app a person's place links open: "google" or "apple" (#301).
  def change do
    alter table(:users) do
      add :maps_app, :string, null: false, default: "google"
    end
  end
end
