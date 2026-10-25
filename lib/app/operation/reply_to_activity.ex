defmodule App.Operation.ReplyToActivity do
  @moduledoc """
  A member replies to an activity they're invited to (#444): `:yes` for I'll be there,
  `:no` for Can't make it. plan/4 makes one `:update_attendance` row for the member's
  existing D4H row, attending with the activity's times or absent. A reply never adds a
  row: being invited means D4H has one. call/6 sends it straight to D4H as a change set
  of source `:member`, where the latest tap wins over D4H's status now, then updates the
  copy so the page shows the reply at once.
  """

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Repo

  @doc """
  `{:ok, attendance}` with the copy updated once D4H took the reply, or `{:error, text}`.
  `user` is nil for a reply from a reminder's link, which needs no login.
  """
  def call(
        %Team{} = team,
        %Activity{team_id: team_id} = activity,
        %Member{team_id: team_id} = member,
        reply,
        user,
        now
      )
      when team_id == team.id and (is_nil(user) or is_struct(user, User)) do
    attendance = Attendance.invitation(activity, member)

    with {:ok, row} <- plan(activity, attendance, reply, now),
         {:ok, row} <- send_row(team, activity, user, row, now) do
      {:ok, update_copy(attendance, activity, row, now)}
    else
      {:error, reason} -> {:error, error_text(reason)}
    end
  end

  @doc """
  The row a reply sends, as `{:ok, %ChangeSetRow{}}`, from the member's invitation
  `attendance` (nil when they aren't invited). `{:error, reason}` for an activity that
  was deleted (`:deleted`) or has started (`:started`), since replies close at the start,
  or a member with no invitation (`:not_invited`).
  """
  def plan(%Activity{} = activity, attendance, reply, %DateTime{} = now)
      when reply in [:yes, :no] do
    cond do
      activity.deleted_at -> {:error, :deleted}
      not DateTime.before?(now, activity.started_at) -> {:error, :started}
      attendance == nil -> {:error, :not_invited}
      true -> {:ok, row(activity, attendance, reply)}
    end
  end

  defp row(activity, %Attendance{} = attendance, reply) do
    %ChangeSetRow{
      member_id: attendance.member_id,
      action: :update_attendance,
      d4h_record_id: attendance.d4h_attendance_id,
      old_value: %{
        "status" => attendance.status,
        "starts_at" => ApplyChangeSet.iso(attendance.started_at),
        "ends_at" => ApplyChangeSet.iso(attendance.finished_at)
      },
      new_value: new_value(activity, reply)
    }
  end

  defp new_value(activity, :yes) do
    %{
      "status" => "ATTENDING",
      "starts_at" => ApplyChangeSet.iso(activity.started_at),
      "ends_at" => ApplyChangeSet.iso(activity.finished_at)
    }
  end

  defp new_value(_activity, :no), do: %{"status" => "ABSENT"}

  defp send_row(team, activity, user, row, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :member,
          activity_id: activity.id,
          proposed_by_user_id: user && user.id
        },
        [row]
      )

    case ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, [%ChangeSetRow{status: :applied} = row]} -> {:ok, row}
      {:ok, [%ChangeSetRow{status: :skipped}]} -> {:error, :gone}
      {:ok, [%ChangeSetRow{status: :failed}]} -> {:error, :failed}
      {:error, reason} -> {:error, reason}
    end
  end

  # The copy takes what D4H was sent, so the next sync sees nothing new. The copy holds
  # D4H's status lowercased. Absent keeps the row's times, as D4H does.
  defp update_copy(attendance, activity, %ChangeSetRow{new_value: new_value}, now) do
    changes = %{
      status: String.downcase(new_value["status"]),
      replied_at: DateTime.truncate(now, :second)
    }

    changes =
      if new_value["starts_at"],
        do:
          Map.merge(changes, %{
            started_at: activity.started_at,
            finished_at: activity.finished_at,
            duration_in_minutes:
              Service.Convert.duration_to_minutes(activity.started_at, activity.finished_at)
          }),
        else: changes

    attendance |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  defp error_text(reason) do
    case reason do
      :started -> "Replies closed when the activity started."
      :deleted -> "This activity is deleted."
      :not_invited -> "Only invited members can reply."
      :gone -> "Your invitation was deleted. Ask a team admin."
      :published -> "Your reply cannot be sent. This activity is published."
      :no_team_key -> "Your team has no access key. Ask a team admin."
      _failed -> "Your reply was not sent. Try again, or ask a team admin."
    end
  end
end
