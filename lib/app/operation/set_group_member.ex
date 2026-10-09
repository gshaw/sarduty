defmodule App.Operation.SetGroupMember do
  @moduledoc """
  A team admin adds a hosted team's member to a group, or removes them
  (docs/hosted-d4h.md). The same row actions group rules use, one row at a time, applied
  through App.Operation.ApplyEdit.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Group
  alias App.Model.GroupMember
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

    with {:ok, _id} <- ApplyEdit.call(team, user, row, now, group_id: group.id), do: :ok
  end

  def remove(%Team{} = team, %GroupMember{} = group_member, %User{} = user, now) do
    group_member = Repo.preload(group_member, [:group, :member])
    true = group_member.group.team_id == team.id

    row = %ChangeSetRow{
      action: :remove_group_member,
      member_id: group_member.member_id,
      d4h_record_id: group_member.d4h_group_membership_id,
      old_value: %{"d4h_group_id" => group_member.group.d4h_group_id},
      new_value: %{}
    }

    with {:ok, _id} <- ApplyEdit.call(team, user, row, now, group_id: group_member.group_id),
         do: :ok
  end
end
