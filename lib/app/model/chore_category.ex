defmodule App.Model.ChoreCategory do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.ChoreCategory
  alias App.Model.ChoreCategoryTag
  alias App.Model.Team
  alias App.Repo

  # What a member picks when they log a chore (#341). Each month, each category is its own
  # D4H event, tagged with its hours tag and its other tags when the event is made. The
  # hours tag is a kind, not a title, so a renamed hours tag still works. Archived, never
  # deleted: old chores keep their category, and members cannot pick it.
  schema "chore_categories" do
    belongs_to :team, Team
    has_many :chore_category_tags, ChoreCategoryTag, on_replace: :delete
    field :title, TrimmedString
    field :hours, Ecto.Enum, values: [:primary, :secondary]
    field :archived_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:title, :hours])
    |> validate_required([:title], message: "Enter a name for the category")
    |> validate_required([:hours], message: "Select which hours the chores count for")
    |> validate_length(:title, max: 100)
  end

  @doc "A team's chore categories by title, archived ones last, with their tags."
  def get_all(team_id) do
    ChoreCategory
    |> where([c], c.team_id == ^team_id)
    |> order_by([c], asc: not is_nil(c.archived_at), asc: c.title, asc: c.id)
    |> preload(chore_category_tags: :tag)
    |> Repo.all()
  end

  @doc "The categories a member can pick: not archived, by title."
  def get_open(team_id) do
    ChoreCategory
    |> where([c], c.team_id == ^team_id and is_nil(c.archived_at))
    |> order_by([c], asc: c.title, asc: c.id)
    |> Repo.all()
  end

  def find!(%Team{} = team, id) do
    ChoreCategory
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload(chore_category_tags: :tag)
  end

  @doc "The category's other tags by title."
  def tags(%ChoreCategory{chore_category_tags: category_tags}),
    do: category_tags |> Enum.map(& &1.tag) |> Enum.sort_by(&String.downcase(&1.title))

  def archived?(%ChoreCategory{archived_at: archived_at}), do: not is_nil(archived_at)
end
