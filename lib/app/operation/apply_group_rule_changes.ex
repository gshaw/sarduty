defmodule App.Operation.ApplyGroupRuleChanges do
  alias App.Accounts.User
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo

  @doc """
  Sends the group's planned adds and removes to D4H as a change set, for the members
  the user ticked. The plan is rebuilt here, so a member id the browser sent that isn't
  in the plan is ignored. Each change updates the local copy and is logged on the
  group, and a failed one doesn't stop the rest.
  """
  def call(%Team{} = team, %Group{} = group, %User{} = user, selected_member_ids) do
    preview = BuildGroupRulePreview.for_group(team, group)

    cond do
      is_nil(team.d4h_access_key) ->
        {:error, :no_team_key}

      preview.missing_qualification_ids != [] ->
        {:error, :rules_broken}

      true ->
        apply_selected(team, group, user, select_changes(preview, selected_member_ids))
    end
  end

  defp apply_selected(team, group, user, changes) do
    # A refresh between the preview and the click may have removed a membership
    # already. That counts as done, with nothing to send.
    {to_send, gone} =
      changes
      |> Enum.map(&Map.put(&1, :group_member, group_member(group, &1.member)))
      |> Enum.split_with(&(&1.action == :add or &1.group_member))

    with {:ok, results} <- send_changes(team, group, user, to_send, DateTime.utc_now()) do
      {:ok, log_all(group, user, results ++ Enum.map(gone, &{&1, nil}))}
    end
  end

  defp log_all(group, user, results) do
    Enum.each(results, &log(group, user, &1))
    failed = Enum.count(results, &elem(&1, 1))
    %{applied: length(results) - failed, failed: failed}
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

  defp group_member(group, member),
    do: GroupMember.get_by(group_id: group.id, member_id: member.id)

  defp send_changes(_team, _group, _user, [], _now), do: {:ok, []}

  defp send_changes(team, group, user, changes, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :group_rule,
          group_id: group.id,
          proposed_by_user_id: user.id
        },
        Enum.map(changes, &change_set_row(group, &1))
      )

    with {:ok, rows} <- ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, Enum.zip_with(changes, rows, &update_local_copy(group, &1, &2))}
    end
  end

  defp change_set_row(group, change) do
    new_value = %{
      "d4h_group_id" => group.d4h_group_id,
      "d4h_member_id" => change.member.d4h_member_id
    }

    in_group = change.action == :add

    %ChangeSetRow{
      member_id: change.member.id,
      action: if(in_group, do: :add_group_member, else: :remove_group_member),
      d4h_record_id: change.group_member && change.group_member.d4h_group_membership_id,
      old_value: %{"in_group" => not in_group},
      new_value: Map.put(new_value, "in_group", in_group),
      reason: change.reason
    }
  end

  # Returns the change with D4H's error, or nil when it went through.
  defp update_local_copy(group, change, %ChangeSetRow{status: :applied} = row) do
    case change.action do
      :add ->
        params = %{
          group_id: group.id,
          member_id: change.member.id,
          d4h_group_membership_id: row.d4h_record_id
        }

        case change.group_member do
          nil -> GroupMember.insert!(params)
          group_member -> GroupMember.update!(group_member, params)
        end

      :remove ->
        Repo.delete!(change.group_member)
    end

    {change, nil}
  end

  defp update_local_copy(_group, change, %ChangeSetRow{error: error}), do: {change, error}

  defp log(group, user, {change, error}) do
    GroupMembershipChange.insert!(%GroupMembershipChange{
      team_id: group.team_id,
      d4h_group_id: group.d4h_group_id,
      member_id: change.member.id,
      user_id: user.id,
      action: change.action,
      reason: change.reason,
      error: error
    })
  end
end
