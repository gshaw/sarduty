defmodule Web.ActivityMembersLive.Attended do
  @moduledoc """
  Marks the checked members attended, with the activity's times (#766), in place:
  App.Operation.ChangeAttendance's `:attended`. It passes over the attended, and greys
  out when everyone checked attended already.
  """
  @behaviour Web.ActivityMembersLive.Action

  alias App.Operation.ChangeAttendance
  alias Service.Format
  alias Web.ActivityMembersLive.Action

  @impl Action
  def value, do: "attended"

  @impl Action
  def label, do: "Mark attended"

  @impl Action
  def hint(ctx, []), do: "Gives the checked the activity's times, #{times(ctx)}."

  def hint(ctx, checked) do
    already = Enum.count(checked, &(&1.status == "attending"))

    [
      "Gives the #{count(ctx, checked)} checked the activity's times, #{times(ctx)}.",
      already > 0 && "#{already} attended already."
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  defp times(%{activity: activity, team: team}),
    do:
      "#{Format.time_short(activity.started_at, team.timezone)} to #{Format.time_short(activity.finished_at, team.timezone)}"

  @impl Action
  def unavailable(_ctx, []), do: nil

  def unavailable(ctx, checked),
    do: if(count(ctx, checked) == 0, do: "Everyone checked attended already.")

  @impl Action
  def offered?(%{activity: activity, now: now}), do: ChangeAttendance.open?(activity, now)

  @impl Action
  def count(_ctx, checked),
    do: Enum.count(checked, &ChangeAttendance.changes?(:attended, &1.status))

  @impl Action
  def button_text(count), do: "Mark #{count} attended"

  @impl Action
  def variant, do: :primary

  @impl Action
  def confirm(_ctx, _checked), do: %{}

  @impl Action
  def run(_checked), do: {:in_place, :attended}
end
