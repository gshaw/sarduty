defmodule App.Operation.RefreshD4HData.UpsertMembers do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.RecordD4HChanges
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.StaleRows
  alias App.Repo

  require Logger

  @chunk_size 100

  def call(d4h, team, progress) do
    d4h_members = D4H.fetch_team_members(d4h)
    total_count = Enum.count(d4h_members)

    progress = Progress.update_stage(progress, "Members", total_count)

    chunks = Enum.chunk_every(d4h_members, @chunk_size)

    progress =
      Enum.reduce(chunks, progress, fn chunk, progress_acc ->
        Enum.each(chunk, &upsert_member(team, &1))
        Progress.add_page(progress_acc, Enum.count(chunk))
      end)

    if d4h_members != [] do
      synced_d4h_ids = MapSet.new(d4h_members, & &1.d4h_member_id)
      mark_departed(team.id, synced_d4h_ids, DateTime.utc_now(:second))
    end

    {total_count, progress}
  end

  # D4H leaves deleted members out of `GET /members`. Attendance and letters point at
  # them, so they stay, marked as left. If D4H lists one again, the upsert takes its
  # `endsAt` back. An empty list is never a real team, so `call` skips this for one.
  def mark_departed(team_id, synced_d4h_ids, now) do
    stale_ids =
      Member
      |> where([m], m.team_id == ^team_id and is_nil(m.left_at))
      |> StaleRows.ids(:d4h_member_id, synced_d4h_ids)

    departed = Member |> where([m], m.id in ^stale_ids) |> Repo.all()

    {count, _} =
      Member
      |> where([m], m.id in ^stale_ids)
      |> Repo.update_all(set: [left_at: now, updated_at: DateTime.utc_now()])

    Enum.each(departed, &RecordD4HChanges.record(:member, &1, %{&1 | left_at: now}))

    Logger.info("Marked #{count} members D4H no longer lists as departed for team #{team_id}")
  end

  defp upsert_member(team, d4h_member) do
    params = %{
      team_id: team.id,
      d4h_member_id: d4h_member.d4h_member_id,
      ref_id: d4h_member.ref_id,
      name: d4h_member.name,
      email: d4h_member.email,
      phone: d4h_member.phone,
      address: d4h_member.address,
      position: d4h_member.position,
      joined_at: d4h_member.joined_at,
      left_at: d4h_member.left_at,
      d4h_permission: d4h_member.permission,
      d4h_status: d4h_member.status
    }

    member = Member.get_by(team_id: team.id, d4h_member_id: d4h_member.d4h_member_id)

    saved = if member, do: Member.update!(member, params), else: Member.insert!(params)
    RecordD4HChanges.record(:member, member, saved)

    # This is how to do an actual upsert but it doesn't set updated_at correctly.
    #
    # Repo.insert!(
    #   Member.build_new_changeset(Map.new(params)),
    #   on_conflict: [set: params],
    #   conflict_target: [:team_id, :d4h_id]
    # )
  end
end
