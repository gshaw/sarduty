defmodule App.Model.Kit do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Kit
  alias App.Model.KitItem
  alias App.Model.Team
  alias App.Repo

  # A named set of equipment items, each with default hours, that a team admin adds to
  # an activity in one step (#271). Kits are SAR Duty's own; D4H never sees them.
  schema "kits" do
    belongs_to :team, Team
    has_many :kit_items, KitItem, on_replace: :delete
    field :title, TrimmedString
    timestamps(type: :utc_datetime_usec)
  end

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:title])
    |> validate_required([:title], message: "Enter a name for the kit")
    |> validate_length(:title, max: 100)
  end

  @doc "A team's kits by title, with their items."
  def get_all(team_id) do
    Kit
    |> where([k], k.team_id == ^team_id)
    |> order_by([k], asc: k.title, asc: k.id)
    |> preload(kit_items: :equipment_item)
    |> Repo.all()
  end

  def find!(%Team{} = team, id) do
    Kit
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload(kit_items: :equipment_item)
  end
end
