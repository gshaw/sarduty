defmodule App.Model.LocationBookmark do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.LocationBookmark
  alias App.Model.Team
  alias App.Repo

  # A copy of one of the team's own D4H location bookmarks (#614), kept by the sync: a
  # title for a place, with its address and pin. Archived ones are not kept.
  schema "location_bookmarks" do
    belongs_to :team, Team
    field :d4h_location_bookmark_id, :integer
    field :title, TrimmedString
    field :address, :string
    field :coordinate, :string
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The team's bookmarks in D4H's order: by title, so a leading `!` comes first."
  def get_all(%Team{} = team) do
    LocationBookmark
    |> where([b], b.team_id == ^team.id)
    |> order_by([b], asc: b.title, asc: b.id)
    |> Repo.all()
  end

  @doc """
  The title to show. Teams start a title with `!` to sort it to the top of D4H's list,
  so that is left off.
  """
  def name(%LocationBookmark{title: title}),
    do: title |> String.trim_leading("!") |> String.trim_leading()
end
