defmodule App.Model.Tag do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Repo

  # A copy of one of the team's D4H tags (#162), kept by the sync. Kits point at it.
  # Activities still store their tags as titles.
  schema "tags" do
    belongs_to :team, Team
    field :d4h_tag_id, :integer
    field :title, TrimmedString
    # "Team" or "Organisation" and its D4H id; an organisation's tags are read-only to
    # its teams (#289).
    field :owner_type, :string
    field :owner_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  @doc "A team's tags by title."
  def get_all(team_id) do
    Tag
    |> where([t], t.team_id == ^team_id)
    |> order_by([t], asc: t.title, asc: t.id)
    |> Repo.all()
  end
end
