defmodule App.Operation.SetGroupMembers do
  @moduledoc """
  A team admin adds the members they ticked on the Members list to a group kept by hand,
  or removes them from it (#547). One change set, source `:edit` like
  App.Operation.SetGroupMember's single changes, with the group on it so History names
  it. A failed row doesn't stop the rest. Each applied row changes the local copy at once
  and every row is logged with the group's recent changes, as group rules do.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
  alias App.Model.GroupRule
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.SetGroupMember
  alias App.Repo

  @doc """
  The group and member ids come from the browser, so each is looked up through the team.
  `{:ok, %{group:, done:, skipped:, failed:}}`, members by name, `failed` as
  `{member, text}`; or `{:error, text}` to show the person.
  """
  def call(%Team{} = team, action, group_id, member_ids, %User{} = user, now)
      when action in [:add, :remove] do
    with {:ok, group} <- find_group(team, group_id),
         {:ok, members} <- find_members(team, member_ids),
         :ok <- check_adding(team, action, group, members, now),
         do: apply_plan(team, group, user, plan(action, members, group_members(group)), now)
  end

  defp apply_plan(team, group, user, %{action: action} = plan, now) do
    with {:ok, results} <- send_changes(team, group, user, action, plan.changes, now) do
      Enum.each(results, &log(group, user, action, &1))
      {:ok, Map.merge(%{group: group, skipped: plan.skipped}, sort_results(results))}
    end
  end

  defp sort_results(results) do
    {failed, done} = Enum.split_with(results, &elem(&1, 1))

    %{
      done: Enum.map(done, fn {change, nil} -> change.member end),
      failed: Enum.map(failed, fn {change, text} -> {change.member, text} end)
    }
  end

  @doc """
  Which members to change and which to skip: adding skips members in the group already,
  removing skips members who aren't in it. `group_members` are the group's rows now.
  """
  def plan(action, members, group_members) do
    by_member = Map.new(group_members, &{&1.member_id, &1})

    {changes, skipped} =
      members
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&%{member: &1, group_member: by_member[&1.id]})
      |> Enum.split_with(&(action == :add == is_nil(&1.group_member)))

    %{action: action, changes: changes, skipped: Enum.map(skipped, & &1.member)}
  end

  defp check_adding(team, :add, group, members, now),
    do: SetGroupMember.check_keeps_a_team_admin(team, group, members, now)

  defp check_adding(_team, :remove, _group, _members, _now), do: :ok

  defp find_group(team, id) do
    case id && Repo.get_by(Group, id: id, team_id: team.id) do
      nil -> {:error, "Select a group."}
      group -> if GroupRule.ruled?(group), do: {:error, ruled(group)}, else: {:ok, group}
    end
  end

  defp ruled(group), do: "#{group.title} has rules, which decide who is in it."

  defp find_members(_team, []), do: {:error, "Select members."}

  defp find_members(team, ids) do
    case Member |> where([m], m.team_id == ^team.id and m.id in ^ids) |> Repo.all() do
      [] -> {:error, "Select members."}
      members -> {:ok, members}
    end
  end

  defp group_members(group), do: GroupMember |> where(group_id: ^group.id) |> Repo.all()

  defp send_changes(_team, _group, _user, _action, [], _now), do: {:ok, []}

  defp send_changes(team, group, user, action, changes, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :edit,
          group_id: group.id,
          proposed_by_user_id: user.id
        },
        Enum.map(changes, &row(group, action, &1))
      )

    case ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, rows} -> {:ok, Enum.zip_with(changes, rows, &update_local_copy(group, &1, &2))}
      {:error, :no_team_key} -> {:error, "This team has no key. Ask a SAR Duty site admin."}
    end
  end

  defp row(group, :add, change) do
    %ChangeSetRow{
      action: :add_group_member,
      member_id: change.member.id,
      old_value: %{},
      new_value: %{
        "d4h_group_id" => group.d4h_group_id,
        "d4h_member_id" => change.member.d4h_member_id
      }
    }
  end

  defp row(group, :remove, change) do
    %ChangeSetRow{
      action: :remove_group_member,
      member_id: change.member.id,
      d4h_record_id: change.group_member.d4h_group_membership_id,
      old_value: %{"d4h_group_id" => group.d4h_group_id},
      new_value: %{}
    }
  end

  # The change with D4H's error, or nil when it went through.
  defp update_local_copy(group, change, %ChangeSetRow{status: :applied} = row) do
    case row.action do
      # The sync may have copied it first.
      :add_group_member ->
        params = %{
          group_id: group.id,
          member_id: change.member.id,
          d4h_group_membership_id: row.d4h_record_id
        }

        case GroupMember.get_by(group_id: group.id, member_id: change.member.id) do
          nil -> GroupMember.insert!(params)
          group_member -> GroupMember.update!(group_member, params)
        end

      :remove_group_member ->
        Repo.delete!(change.group_member, allow_stale: true)
    end

    {change, nil}
  end

  defp update_local_copy(_group, change, %ChangeSetRow{error: error}), do: {change, error}

  defp log(group, user, action, {change, error}) do
    GroupMembershipChange.insert!(%GroupMembershipChange{
      team_id: group.team_id,
      d4h_group_id: group.d4h_group_id,
      member_id: change.member.id,
      user_id: user.id,
      action: action,
      error: error
    })
  end
end
