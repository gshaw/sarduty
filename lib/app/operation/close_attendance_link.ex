defmodule App.Operation.CloseAttendanceLink do
  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.Team

  @doc "Stops the activity's link working. Scans already taken stay."
  def call(%Team{} = team, %Activity{team_id: team_id} = activity, now)
      when team_id == team.id do
    AttendanceLink.close_all!(team, activity, now)
    :ok
  end
end
