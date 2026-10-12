defmodule App.Operation.RefreshD4HData.UpsertTags do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Tag
  alias App.Operation.RefreshD4HData.StaleRows
  alias App.Repo

  require Logger

  @doc """
  Fetches the team's tags, keeps a copy in `tags` (#162), and returns them as a map of
  D4H id to title, the index activities need. A tag D4H no longer has is deleted, and
  leaves its kits.
  """
  def call(d4h, team) do
    d4h_tags = D4H.fetch_tags(d4h)
    save(team.id, d4h_tags, DateTime.utc_now())
    Map.new(d4h_tags, &{&1.d4h_tag_id, &1.title})
  end

  def save(team_id, d4h_tags, now) do
    rows =
      d4h_tags
      |> Enum.uniq_by(& &1.d4h_tag_id)
      |> Enum.map(fn tag ->
        %{
          team_id: team_id,
          d4h_tag_id: tag.d4h_tag_id,
          title: tag.title,
          owner_type: tag.owner_type,
          owner_id: tag.owner_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(100)
    |> Enum.each(
      &Repo.insert_all(Tag, &1,
        on_conflict: {:replace, [:title, :owner_type, :owner_id, :updated_at]},
        conflict_target: [:team_id, :d4h_tag_id]
      )
    )

    delete_stale(team_id, MapSet.new(rows, & &1.d4h_tag_id))
  end

  defp delete_stale(team_id, synced_d4h_ids) do
    stale_ids =
      Tag
      |> where([t], t.team_id == ^team_id)
      |> StaleRows.ids(:d4h_tag_id, synced_d4h_ids)

    if stale_ids != [] do
      {count, _} = Tag |> where([t], t.id in ^stale_ids) |> Repo.delete_all()
      Logger.info("Deleted #{count} stale tags for team #{team_id}")
    end
  end
end
