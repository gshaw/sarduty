defmodule App.Operation.RefreshD4HData.UpsertMembers do
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.RefreshD4HData.Progress

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

    {total_count, progress}
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
      left_at: d4h_member.left_at
    }

    member = Member.get_by(team_id: team.id, d4h_member_id: d4h_member.d4h_member_id)

    if member do
      Member.update!(member, params)
    else
      Member.insert!(params)
    end

    # This is how to do an actual upsert but it doesn't set updated_at correctly.
    #
    # Repo.insert!(
    #   Member.build_new_changeset(Map.new(params)),
    #   on_conflict: [set: params],
    #   conflict_target: [:team_id, :d4h_id]
    # )
  end
end
