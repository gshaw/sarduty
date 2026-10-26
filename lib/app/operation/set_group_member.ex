defmodule App.Operation.SetGroupMember do
  @moduledoc """
  A team admin adds a member to a group kept by hand, or removes them (#546). The same row
  actions group rules use, one row at a time, applied through App.Operation.ApplyEdit.
  Then the local copy changes at once, as group rules do, and the change is logged with
  the group's recent changes, without a reason. A group with rules changes only through
  Review changes, so it is refused here.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
  alias App.Model.GroupRule
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Repo

  @doc "`:ok` or `{:error, text}`."
  def add(
        %Team{} = team,
        %Member{team_id: team_id} = member,
        %Group{team_id: team_id} = group,
        %User{} = user,
        now
      )
      when team_id == team.id do
    row = %ChangeSetRow{
      action: :add_group_member,
      member_id: member.id,
      old_value: %{},
      new_value: %{"d4h_group_id" => group.d4h_group_id, "d4h_member_id" => member.d4h_member_id}
    }

    with :ok <- check_kept_by_hand(group) do
      result = ApplyEdit.call(team, user, row, now, group_id: group.id)
      with {:ok, d4h_id} <- result, do: save_local(group, member, d4h_id)
      log(result, team, member.id, group.d4h_group_id, :add, user)
    end
  end

  def remove(%Team{} = team, %GroupMember{} = group_member, %User{} = user, now) do
    group_member = Repo.preload(group_member, [:group, :member])
    %Group{team_id: team_id} = group = group_member.group
    true = team_id == team.id

    row = %ChangeSetRow{
      action: :remove_group_member,
      member_id: group_member.member_id,
      d4h_record_id: group_member.d4h_group_membership_id,
      old_value: %{"d4h_group_id" => group.d4h_group_id},
      new_value: %{}
    }

    with :ok <- check_kept_by_hand(group) do
      result = ApplyEdit.call(team, user, row, now, group_id: group.id)
      with {:ok, _id} <- result, do: Repo.delete(group_member, allow_stale: true)
      log(result, team, group_member.member_id, group.d4h_group_id, :remove, user)
    end
  end

  # The sync may have copied it first.
  defp save_local(group, member, d4h_id) do
    params = %{group_id: group.id, member_id: member.id, d4h_group_membership_id: d4h_id}

    case GroupMember.get_by(group_id: group.id, member_id: member.id) do
      nil -> GroupMember.insert!(params)
      group_member -> GroupMember.update!(group_member, params)
    end
  end

  defp check_kept_by_hand(group),
    do: if(GroupRule.ruled?(group), do: {:error, "Its rules decide who is in it."}, else: :ok)

  defp log(result, team, member_id, d4h_group_id, action, user) do
    GroupMembershipChange.insert!(%GroupMembershipChange{
      team_id: team.id,
      member_id: member_id,
      user_id: user.id,
      d4h_group_id: d4h_group_id,
      action: action,
      error:
        case result do
          {:error, text} -> text
          {:ok, _id} -> nil
        end
    })

    with {:ok, _id} <- result, do: :ok
  end
end
