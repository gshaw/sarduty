defmodule App.Repo.Migrations.CreateHomeCoordinatesAndRouteDistances do
  use Ecto.Migration

  # Saved Mapbox lookups for mileage (#230), so the report reads them instead of asking
  # again. A home is looked up again only when the member's address changes. A route is
  # one way, between two "lat,lng" points at 5 places; metres is nil when Mapbox found
  # none.
  def change do
    create table(:home_coordinates) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :address, :string
      add :coordinate, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:home_coordinates, [:member_id])
    create index(:home_coordinates, [:team_id])

    create table(:route_distances) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :origin, :string, null: false
      add :destination, :string, null: false
      add :metres, :integer
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:route_distances, [:team_id, :origin, :destination])
  end
end
