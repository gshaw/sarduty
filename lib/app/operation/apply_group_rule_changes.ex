defmodule App.Operation.ApplyGroupRuleChanges do
  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
  alias App.Model.Team
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo

  @doc """
  Sends the group's planned adds and removes to D4H with the team's key, for the
  members the user ticked. The plan is rebuilt here, so a member id the browser sent
  that isn't in the plan is ignored. Each change updates the local copy and is logged,
  and a failed one doesn't stop the rest.
  """
  def call(%Team{} = team, %Group{} = group, %User{} = user, selected_member_ids) do
    preview = BuildGroupRulePreview.for_group(team, group)

    cond do
      is_nil(team.d4h_access_key) ->
        {:error, :no_team_key}

      preview.missing_qualification_ids != [] ->
        {:error, :rules_broken}

      true ->
        d4h = D4H.build_context_from_team(team)

        results =
          preview
          |> select_changes(selected_member_ids)
          |> Enum.map(&apply_change(d4h, group, user, &1))

        {:ok,
         %{applied: Enum.count(results, &(&1 == :ok)), failed: Enum.count(results, &(&1 != :ok))}}
    end
  end

  @doc "The preview's changes for the ticked members, removals first."
  def select_changes(preview, selected_member_ids) do
    selected = MapSet.new(selected_member_ids)

    for {action, rows} <- [remove: preview.to_remove, add: preview.to_add],
        row <- rows,
        MapSet.member?(selected, row.member.id) do
      %{action: action, member: row.member, reason: row.reason}
    end
  end

  defp apply_change(d4h, group, user, change) do
    error =
      case send_change(d4h, group, change) do
        :ok -> nil
        {:error, error} -> Exception.message(error)
      end

    GroupMembershipChange.insert!(%GroupMembershipChange{
      team_id: group.team_id,
      d4h_group_id: group.d4h_group_id,
      member_id: change.member.id,
      user_id: user.id,
      action: change.action,
      reason: change.reason,
      error: error
    })

    if error, do: :error, else: :ok
  end

  defp send_change(d4h, group, %{action: :add, member: member}) do
    with {:ok, membership} <- D4H.add_group_member(d4h, group.d4h_group_id, member.d4h_member_id) do
      params = %{
        group_id: group.id,
        member_id: member.id,
        d4h_group_membership_id: membership.d4h_group_membership_id
      }

      case GroupMember.get_by(group_id: group.id, member_id: member.id) do
        nil -> GroupMember.insert!(params)
        group_member -> GroupMember.update!(group_member, params)
      end

      :ok
    end
  end

  # A refresh between the preview and the click may have removed it already.
  defp send_change(d4h, group, %{action: :remove, member: member}) do
    case GroupMember.get_by(group_id: group.id, member_id: member.id) do
      nil ->
        :ok

      group_member ->
        with :ok <- D4H.remove_group_membership(d4h, group_member.d4h_group_membership_id) do
          Repo.delete!(group_member)
          :ok
        end
    end
  end
end
