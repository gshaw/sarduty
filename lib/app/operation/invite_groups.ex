defmodule App.Operation.InviteGroups do
  @moduledoc """
  Invites a template's groups to an activity (#162): each current member of the groups gets an
  attendance row in D4H as "REQUESTED", for the activity's times, and answers it
  themselves. A change set of source `:template`, applied at once.

  plan/3 decides who is invited; call/5 reads the groups and writes.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Repo

  @doc """
  The rows that invite `groups`, each `{%Group{}, [%Member{}]}`, to the activity. A member
  in several groups is invited once, and one already on the activity
  (`on_activity`, member ids) not at all, since D4H would add a second row.
  """
  def plan(%Activity{} = activity, groups, on_activity) do
    on_activity = MapSet.new(on_activity)

    groups
    |> Enum.flat_map(fn {group, members} -> Enum.map(members, &{group, &1}) end)
    |> Enum.uniq_by(fn {_group, member} -> member.id end)
    |> Enum.reject(fn {_group, member} -> MapSet.member?(on_activity, member.id) end)
    |> Enum.map(fn {group, member} -> invite_row(activity, group, member) end)
  end

  defp invite_row(activity, group, member) do
    %ChangeSetRow{
      action: :create_attendance,
      member_id: member.id,
      reason: "In the #{group.title} group",
      new_value: %{
        "d4h_activity_id" => activity.d4h_activity_id,
        "d4h_member_id" => member.d4h_member_id,
        "status" => "REQUESTED",
        "starts_at" => ApplyChangeSet.iso(activity.started_at),
        "ends_at" => ApplyChangeSet.iso(activity.finished_at)
      }
    }
  end

  @doc """
  Invites the groups' current members. `{:ok, rows}`, with no rows when everyone is on
  the activity already, or `{:error, text}` to show.
  """
  def call(%Team{} = team, %Activity{} = activity, groups, %User{} = user, now) do
    groups = Enum.filter(groups, &(&1.team_id == team.id))
    rows = plan(activity, members_by_group(team, groups, now), on_activity(activity))

    if rows == [], do: {:ok, []}, else: apply_rows(team, activity, rows, user, now)
  end

  defp members_by_group(team, groups, now) do
    ids = Enum.map(groups, & &1.id)

    members =
      Member
      |> join(:inner, [m], gm in GroupMember, on: gm.member_id == m.id)
      |> where([m, gm], m.team_id == ^team.id and gm.group_id in ^ids)
      |> Member.current_query(now)
      |> Member.people_query()
      |> order_by([m], asc: m.name)
      |> select([m, gm], {gm.group_id, m})
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    for %Group{} = group <- groups, do: {group, Map.get(members, group.id, [])}
  end

  defp on_activity(activity) do
    Attendance
    |> where([a], a.activity_id == ^activity.id)
    |> select([a], a.member_id)
    |> Repo.all()
  end

  defp apply_rows(team, activity, rows, user, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :template,
          activity_id: activity.id,
          proposed_by_user_id: user.id
        },
        rows
      )

    case ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, rows} -> {:ok, rows}
      {:error, reason} -> {:error, describe(team, reason)}
    end
  end

  defp describe(_team, :no_team_key), do: "Save your team's access key in team settings first."
  defp describe(_team, :deleted), do: "This activity is deleted."

  defp describe(team, :published),
    do:
      "Nobody was invited. Attendance cannot be changed once the activity is published. #{D4H.unpublish_text(team)}"

  defp describe(team, error), do: "Nobody was invited. #{D4H.error_text(team, error)}"
end
