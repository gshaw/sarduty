defmodule App.Operation.RefreshD4HData.UpsertQualificationAwards do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.StaleRows
  alias App.Repo

  require Logger

  def call(d4h, team, progress) when is_map(d4h) when is_map(team) do
    context = %{
      d4h_member_index: build_d4h_member_index(team.id),
      d4h_qualification_index: build_d4h_qualification_index(team.id)
    }

    {count, progress, d4h_award_ids} =
      D4H.reduce_qualification_awards(
        d4h,
        {0, progress, MapSet.new()},
        &upsert_page(context, &1, &2)
      )

    delete_stale(team.id, d4h_award_ids)
    {count, progress}
  end

  def delete_stale(team_id, synced_d4h_ids) do
    stale_ids =
      MemberQualificationAward
      |> join(:inner, [a], m in assoc(a, :member))
      |> join(:inner, [a], q in assoc(a, :qualification))
      |> where([a, m, q], m.team_id == ^team_id and q.team_id == ^team_id)
      |> StaleRows.ids(:d4h_award_id, synced_d4h_ids)

    {count, _} = MemberQualificationAward |> where([a], a.id in ^stale_ids) |> Repo.delete_all()
    Logger.info("Deleted #{count} stale qualification awards for team #{team_id}")
  end

  defp build_d4h_member_index(team_id) do
    team_id
    |> Member.get_all()
    |> Enum.map(fn r -> {r.d4h_member_id, r.id} end)
    |> Map.new()
  end

  defp build_d4h_qualification_index(team_id) do
    team_id
    |> Qualification.get_all()
    |> Enum.map(fn r -> {r.d4h_qualification_id, r.id} end)
    |> Map.new()
  end

  defp upsert_page(context, d4h_awards, {total_count, progress, d4h_award_ids}) do
    count = Enum.count(d4h_awards)
    Enum.each(d4h_awards, &upsert_award(context, &1))
    d4h_award_ids = Enum.into(d4h_awards, d4h_award_ids, & &1.d4h_award_id)
    {total_count + count, Progress.add_page(progress, count), d4h_award_ids}
  end

  defp upsert_award(context, d4h_award) do
    member_id = context.d4h_member_index[d4h_award.d4h_member_id]
    qualification_id = context.d4h_qualification_index[d4h_award.d4h_qualification_id]
    upsert_award(member_id, qualification_id, d4h_award)
  end

  defp upsert_award(nil, _qualification_id, _d4h_award), do: :skip
  defp upsert_award(_member_id, nil, _d4h_award), do: :skip

  defp upsert_award(member_id, qualification_id, d4h_award) do
    params = %{
      member_id: member_id,
      qualification_id: qualification_id,
      d4h_award_id: d4h_award.d4h_award_id,
      starts_at: d4h_award.starts_at,
      ends_at: d4h_award.ends_at
    }

    award =
      MemberQualificationAward.get_by(
        member_id: member_id,
        d4h_award_id: d4h_award.d4h_award_id
      )

    if award do
      MemberQualificationAward.update!(award, params)
    else
      MemberQualificationAward.insert!(params)
    end
  end
end
