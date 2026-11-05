defmodule Web.ActivityMembersLive.Absent do
  @moduledoc """
  Marks the checked members absent, with no hours (#766), in place:
  App.Operation.ChangeAttendance's `:absent`. It passes over the absent.
  """
  @behaviour Web.ActivityMembersLive.Action

  alias App.Operation.ChangeAttendance

  @impl Web.ActivityMembersLive.Action
  def value, do: "absent"

  @impl Web.ActivityMembersLive.Action
  def label, do: "Absent"

  @impl Web.ActivityMembersLive.Action
  def hint(_ctx), do: "They stay on the activity, with no hours."

  @impl Web.ActivityMembersLive.Action
  def offered?(%{activity: activity, now: now}), do: ChangeAttendance.open?(activity, now)

  @impl Web.ActivityMembersLive.Action
  def count(_ctx, checked),
    do: Enum.count(checked, &ChangeAttendance.changes?(:absent, &1.status))

  @impl Web.ActivityMembersLive.Action
  def button_text(count), do: "Mark #{count} absent"

  @impl Web.ActivityMembersLive.Action
  def variant, do: :primary

  @impl Web.ActivityMembersLive.Action
  def confirm(_ctx, _checked), do: %{}

  @impl Web.ActivityMembersLive.Action
  def run, do: {:in_place, :absent}
end
