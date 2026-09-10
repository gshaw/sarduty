defmodule App.Operation.RefreshD4HData.UpsertGroups do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.StaleRows
  alias App.Repo

  require Logger

  @chunk_size 100

  def call(d4h, team, progress) do
    d4h_groups = D4H.fetch_groups(d4h)
    total_count = Enum.count(d4h_groups)

    progress = Progress.update_stage(progress, "Groups", total_count)

    chunks = Enum.chunk_every(d4h_groups, @chunk_size)

    progress =
      Enum.reduce(chunks, progress, fn chunk, progress_acc ->
        Enum.each(chunk, &upsert_group(team, &1))
        Progress.add_page(progress_acc, Enum.count(chunk))
      end)

    delete_stale(team.id, MapSet.new(d4h_groups, & &1.d4h_group_id))
    {total_count, progress}
  end

  # A group deleted in D4H takes its memberships with it. Its rule clauses stay,
  # keyed by D4H id, and nothing shows them.
  def delete_stale(team_id, synced_d4h_ids) do
    stale_ids =
      Group
      |> where([g], g.team_id == ^team_id)
      |> StaleRows.ids(:d4h_group_id, synced_d4h_ids)

    GroupMember |> where([gm], gm.group_id in ^stale_ids) |> Repo.delete_all()
    {count, _} = Group |> where([g], g.id in ^stale_ids) |> Repo.delete_all()
    Logger.info("Deleted #{count} stale groups for team #{team_id}")
  end

  defp upsert_group(team, d4h_group) do
    params = %{
      team_id: team.id,
      d4h_group_id: d4h_group.d4h_group_id,
      title: d4h_group.title
    }

    group =
      Group.get_by(
        team_id: team.id,
        d4h_group_id: d4h_group.d4h_group_id
      )

    if group do
      Group.update!(group, params)
    else
      Group.insert!(params)
    end
  end
end
