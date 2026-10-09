defmodule App.Operation.DeleteActivity do
  @moduledoc """
  A team admin deletes a hosted team's activity (docs/hosted-d4h.md). The store marks it
  deleted, as D4H does, and the sync marks the copy. Its attendance links and scans stay.
  """

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.ChangeSetRow
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Operation.RefreshD4HData.UpsertActivities

  @doc "`{:ok, activity}` or `{:error, text}`."
  def call(%Team{} = team, %Activity{team_id: team_id} = activity, %User{} = user, now)
      when team_id == team.id do
    row = %ChangeSetRow{
      action: :delete_activity,
      d4h_record_id: activity.d4h_activity_id,
      old_value: %{"kind" => activity.activity_kind, "title" => activity.title},
      new_value: %{}
    }

    with {:ok, _id} <- ApplyEdit.call(team, user, row, now, activity_id: activity.id) do
      if Activity.find!(team, activity.id).deleted_at == nil,
        do: UpsertActivities.mark_one_deleted(team, activity.id, now)

      {:ok, Activity.find!(team, activity.id)}
    end
  end
end
