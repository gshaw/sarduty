defmodule App.Model.Tag do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Repo

  # A copy of one of the team's D4H tags (#162), kept by the sync. Templates point at it.
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

  @doc """
  How many of the team's activities since `since` carry each tag, as a map of title to
  count. Activities store tag titles, so this counts titles.
  """
  def use_counts(team_id, %DateTime{} = since) do
    sql = """
    SELECT j.value, count(*) FROM activities a, json_each(a.tags) j
    WHERE a.team_id = ?1 AND a.deleted_at IS NULL AND a.started_at >= ?2
    GROUP BY j.value
    """

    %{rows: rows} = Repo.query!(sql, [team_id, since])
    Map.new(rows, fn [title, count] -> {title, count} end)
  end
end
