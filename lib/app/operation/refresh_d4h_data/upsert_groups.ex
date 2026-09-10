defmodule App.Operation.RefreshD4HData.UpsertGroups do
  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Operation.RefreshD4HData.Progress

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

    {total_count, progress}
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
