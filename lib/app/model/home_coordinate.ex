defmodule App.Model.HomeCoordinate do
  use App, :model

  alias App.Model.HomeCoordinate
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  # Where Mapbox put a member's home, for mileage (#230). `address` is the one it was
  # looked up from, so a changed address is looked up again. `coordinate` is "lat,lng",
  # or nil when Mapbox found no place. SAR Duty's own data: nothing here goes to D4H.
  schema "home_coordinates" do
    belongs_to :team, Team
    belongs_to :member, Member
    field :address, :string, redact: true
    field :coordinate, :string, redact: true
    timestamps(type: :utc_datetime)
  end

  @doc "The team's saved homes for these member ids, by member id."
  def by_member(%Team{} = team, member_ids) do
    query = from(h in HomeCoordinate, where: h.team_id == ^team.id and h.member_id in ^member_ids)

    query
    |> Repo.all()
    |> Map.new(&{&1.member_id, &1})
  end

  @doc "Saves the place Mapbox found for a member's address, replacing an older one."
  def save!(%Team{} = team, %Member{} = member, address, coordinate) do
    %HomeCoordinate{
      team_id: team.id,
      member_id: member.id,
      address: address,
      coordinate: coordinate
    }
    |> Repo.insert!(
      on_conflict: {:replace, [:address, :coordinate, :updated_at]},
      conflict_target: [:member_id]
    )
  end
end
