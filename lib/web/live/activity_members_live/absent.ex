defmodule Web.ActivityMembersLive.Absent do
  @moduledoc """
  Marks the checked members absent, with no hours (#766), in place:
  App.Operation.ChangeAttendance's `:absent`. It passes over the absent, and greys out
  when everyone checked is absent already.
  """
  @behaviour Web.ActivityMembersLive.Action

  alias App.Operation.ChangeAttendance
  alias Service.Format
  alias Web.ActivityMembersLive.Action

  @impl Action
  def value, do: "absent"

  @impl Action
  def label, do: "Mark absent"

  @impl Action
  def hint(_ctx, []), do: "The checked who attended lose their hours. They stay on the activity."

  # "The 2 attended lose their hours, 9h 30m. They stay on the activity. 1 is absent
  # already."
  def hint(_ctx, checked) do
    by_status = Enum.group_by(checked, & &1.status)
    attended = Map.get(by_status, "attending", [])
    no_reply = length(Map.get(by_status, "requested", []))
    absent = length(Map.get(by_status, "absent", []))
    minutes = Enum.sum_by(attended, &(&1.duration_in_minutes || 0))

    [
      attended != [] &&
        "The #{length(attended)} attended #{if length(attended) == 1, do: "loses", else: "lose"} their hours, #{Format.duration(minutes)}.",
      no_reply > 0 &&
        "The #{no_reply} with no reply #{if no_reply == 1, do: "is", else: "are"} marked absent.",
      "They stay on the activity.",
      absent > 0 && "#{Action.count_verb(absent, "is", "are")} absent already."
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  @impl Action
  def unavailable(_ctx, []), do: nil

  def unavailable(ctx, checked),
    do: if(count(ctx, checked) == 0, do: "Everyone checked is absent already.")

  @impl Action
  def offered?(%{activity: activity, now: now}), do: ChangeAttendance.open?(activity, now)

  @impl Action
  def count(_ctx, checked),
    do: Enum.count(checked, &ChangeAttendance.changes?(:absent, &1.status))

  @impl Action
  def button_text(count), do: "Mark #{count} absent"

  @impl Action
  def variant, do: :primary

  @impl Action
  def confirm(_ctx, _checked), do: %{}

  @impl Action
  def run(_checked), do: {:in_place, :absent}
end
