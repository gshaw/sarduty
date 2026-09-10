defmodule App.Operation.RefreshD4HData.UpsertGroupMemberships do
  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Operation.RefreshD4HData.Progress

  def call(d4h, team, progress) when is_map(d4h) when is_map(team) do
    context = %{
      d4h_member_index: build_d4h_member_index(team.id),
      d4h_group_index: build_d4h_group_index(team.id)
    }

    D4H.reduce_group_memberships(d4h, {0, progress}, &upsert_page(context, &1, &2))
  end

  defp build_d4h_member_index(team_id) do
    team_id
    |> Member.get_all()
    |> Enum.map(fn r -> {r.d4h_member_id, r.id} end)
    |> Map.new()
  end

  defp build_d4h_group_index(team_id) do
    team_id
    |> Group.get_all()
    |> Enum.map(fn r -> {r.d4h_group_id, r.id} end)
    |> Map.new()
  end

  defp upsert_page(context, d4h_memberships, {total_count, progress}) do
    count = Enum.count(d4h_memberships)
    Enum.each(d4h_memberships, &upsert_membership(context, &1))
    {total_count + count, Progress.add_page(progress, count)}
  end

  defp upsert_membership(context, d4h_membership) do
    member_id = context.d4h_member_index[d4h_membership.d4h_member_id]
    group_id = context.d4h_group_index[d4h_membership.d4h_group_id]
    upsert_membership(member_id, group_id, d4h_membership)
  end

  defp upsert_membership(nil, _group_id, _d4h_membership), do: :skip
  defp upsert_membership(_member_id, nil, _d4h_membership), do: :skip

  defp upsert_membership(member_id, group_id, d4h_membership) do
    params = %{
      member_id: member_id,
      group_id: group_id,
      d4h_group_membership_id: d4h_membership.d4h_group_membership_id
    }

    group_member =
      GroupMember.get_by(
        group_id: group_id,
        member_id: member_id
      )

    if group_member do
      GroupMember.update!(group_member, params)
    else
      GroupMember.insert!(params)
    end
  end
end
