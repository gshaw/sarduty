defmodule Web.ActivityMembersLive.Attended do
  @moduledoc """
  Marks the checked members attended, with the activity's times (#766), in place:
  App.Operation.ChangeAttendance's `:attended`. It passes over the attended.
  """
  @behaviour Web.ActivityMembersLive.Action

  alias App.Operation.ChangeAttendance
  alias Service.Format

  @impl Web.ActivityMembersLive.Action
  def value, do: "attended"

  @impl Web.ActivityMembersLive.Action
  def label, do: "Attended"

  @impl Web.ActivityMembersLive.Action
  def hint(%{activity: activity, team: team}),
    do:
      "The activity's times, #{Format.time_short(activity.started_at, team.timezone)} to #{Format.time_short(activity.finished_at, team.timezone)}."

  @impl Web.ActivityMembersLive.Action
  def offered?(%{activity: activity, now: now}), do: ChangeAttendance.open?(activity, now)

  @impl Web.ActivityMembersLive.Action
  def count(_ctx, checked),
    do: Enum.count(checked, &ChangeAttendance.changes?(:attended, &1.status))

  @impl Web.ActivityMembersLive.Action
  def button_text(count), do: "Mark #{count} attended"

  @impl Web.ActivityMembersLive.Action
  def variant, do: :primary

  @impl Web.ActivityMembersLive.Action
  def confirm(_ctx, _checked), do: %{}

  @impl Web.ActivityMembersLive.Action
  def run, do: {:in_place, :attended}
end
