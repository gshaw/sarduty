defmodule App.Operation.RefreshD4HData.UpsertQualificationAwards do
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification

  def call(d4h, team) when is_map(d4h) when is_map(team) do
    context = %{
      d4h: d4h,
      team_id: team.id,
      d4h_member_index: build_d4h_member_index(team.id),
      d4h_qualification_index: build_d4h_qualification_index(team.id)
    }

    fetch_and_upsert(context, 0)
  end

  defp fetch_and_upsert(context, page) do
    d4h_awards = D4H.fetch_qualification_awards(context.d4h, page)
    upsert_awards(context, page, d4h_awards)
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

  defp upsert_awards(_context, _page, []), do: :ok

  defp upsert_awards(context, page, d4h_awards) do
    Enum.each(d4h_awards, &upsert_award(context, &1))
    fetch_and_upsert(context, page + 1)
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
