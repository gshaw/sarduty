defmodule App.Model.RouteDistance do
  use App, :model

  alias App.Model.RouteDistance
  alias App.Model.Team
  alias App.Repo

  # One way by car between two points, as Mapbox found it, for mileage (#230). `origin`
  # and `destination` are "lat,lng" at 5 places, and one is usually a member's home;
  # `metres` is nil when Mapbox found no route. Never changed once saved: a moved point
  # is a new pair.
  schema "route_distances" do
    belongs_to :team, Team
    field :origin, :string, redact: true
    field :destination, :string, redact: true
    field :metres, :integer
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The team's saved distances for these `{origin, destination}` pairs, by pair."
  def by_pair(%Team{}, []), do: %{}

  def by_pair(%Team{} = team, pairs) do
    origins = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    query = from(r in RouteDistance, where: r.team_id == ^team.id and r.origin in ^origins)

    query
    |> Repo.all()
    |> Map.new(&{{&1.origin, &1.destination}, &1.metres})
    |> Map.take(pairs)
  end

  @doc "Saves what Mapbox found for each `{origin, destination}` pair: metres, or nil."
  def save_all!(%Team{}, found) when found == %{}, do: :ok

  def save_all!(%Team{} = team, found) do
    now = DateTime.utc_now(:second)

    rows =
      for {{origin, destination}, metres} <- found,
          do: %{
            team_id: team.id,
            origin: origin,
            destination: destination,
            metres: metres,
            inserted_at: now
          }

    Repo.insert_all(RouteDistance, rows, on_conflict: :nothing)
    :ok
  end
end
