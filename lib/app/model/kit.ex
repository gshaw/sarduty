defmodule App.Model.Kit do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Kit
  alias App.Model.KitGroup
  alias App.Model.KitItem
  alias App.Model.KitTag
  alias App.Model.Team
  alias App.Repo

  # A named set of equipment items, each with default hours, tags, and groups to invite,
  # that a team admin adds to an activity in one step (#271, #162). Kits are SAR Duty's
  # own; D4H never sees them.
  schema "kits" do
    belongs_to :team, Team
    has_many :kit_items, KitItem, on_replace: :delete
    has_many :kit_tags, KitTag, on_replace: :delete
    has_many :kit_groups, KitGroup, on_replace: :delete
    field :title, TrimmedString
    timestamps(type: :utc_datetime_usec)
  end

  @preloads [kit_items: :equipment_item, kit_tags: :tag, kit_groups: :group]

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:title])
    |> validate_required([:title], message: "Enter a name for the kit")
    |> validate_length(:title, max: 100)
  end

  @doc "A team's kits by title, with their items, tags, and groups."
  def get_all(team_id) do
    Kit
    |> where([k], k.team_id == ^team_id)
    |> order_by([k], asc: k.title, asc: k.id)
    |> preload(^@preloads)
    |> Repo.all()
  end

  def find!(%Team{} = team, id) do
    Kit
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload(@preloads)
  end

  @doc "The kit's tags by title."
  def tags(%Kit{kit_tags: kit_tags}),
    do: kit_tags |> Enum.map(& &1.tag) |> Enum.sort_by(&String.downcase(&1.title))

  @doc "The groups the kit invites, by title."
  def groups(%Kit{kit_groups: kit_groups}),
    do: kit_groups |> Enum.map(& &1.group) |> Enum.sort_by(&String.downcase(&1.title))
end
