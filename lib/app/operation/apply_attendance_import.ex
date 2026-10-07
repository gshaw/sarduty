defmodule App.Operation.ApplyAttendanceImport do
  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Repo

  @doc """
  Sends the ticked changes from a pasted attendance report to D4H as a change set.
  Each change is a map with `:action` (`:add` marks the row attending, `:remove`
  absent), `:d4h_attendance_id`, `:d4h_member_id`, and `:status`, D4H's status when the
  report was read. `{:ok, [{change, row}]}`, or the error from `ApplyChangeSet.call/4`.
  """
  def call(%Team{} = team, %Activity{team_id: team_id} = activity, %User{} = user, changes, now)
      when team_id == team.id and changes != [] do
    member_ids = member_ids(team, changes)

    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :attendance_import,
          activity_id: activity.id,
          proposed_by_user_id: user.id
        },
        Enum.map(changes, &change_set_row(&1, member_ids))
      )

    with {:ok, rows} <- ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, Enum.zip(changes, rows)}
    end
  end

  defp member_ids(team, changes) do
    d4h_member_ids = Enum.map(changes, & &1.d4h_member_id)

    Member
    |> where([m], m.team_id == ^team.id and m.d4h_member_id in ^d4h_member_ids)
    |> select([m], {m.d4h_member_id, m.id})
    |> Repo.all()
    |> Map.new()
  end

  defp change_set_row(change, member_ids) do
    {status, reason} =
      case change.action do
        :add -> {"ATTENDING", "In the attendance report"}
        :remove -> {"ABSENT", "Not in the attendance report"}
      end

    %ChangeSetRow{
      member_id: member_ids[change.d4h_member_id],
      action: :update_attendance,
      d4h_record_id: change.d4h_attendance_id,
      old_value: %{"status" => change.status},
      new_value: %{"status" => status},
      reason: reason
    }
  end
end
