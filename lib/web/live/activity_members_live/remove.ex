defmodule Web.ActivityMembersLive.Remove do
  @moduledoc """
  Takes the checked members off the activity after the start (#766), in place:
  App.Operation.ChangeAttendance's `:remove`. It takes everyone checked, and asks first:
  Add members puts a member back with the activity's times, not their own, so the
  question names any hours that go. No service name, so D4H and Records teams read the
  same.
  """
  @behaviour Web.ActivityMembersLive.Action

  alias App.Operation.ChangeAttendance
  alias Service.Format
  alias Web.ActivityMembersLive.Action

  @impl Action
  def value, do: "remove"

  @impl Action
  def label, do: "Remove from the activity"

  @impl Action
  def hint(_ctx, []),
    do:
      "The checked come off the activity, and lose any hours. Add members puts them back, as attended."

  # "All 3 checked come off the activity, and 2 lose their hours. Add members puts them
  # back, as attended."
  def hint(_ctx, checked) do
    count = length(checked)
    attended = Enum.count(checked, &(&1.status == "attending"))

    off =
      "#{Action.all_checked(count)} #{if count == 1, do: "comes", else: "come"} off the activity"

    off =
      cond do
        attended == 0 -> off <> "."
        attended == count and count == 1 -> off <> ", and loses their hours."
        attended == count -> off <> ", and lose their hours."
        true -> off <> ", and #{Action.count_verb(attended, "loses", "lose")} their hours."
      end

    off <> " Add members puts them back, as attended."
  end

  @impl Action
  def unavailable(_ctx, _checked), do: nil

  @impl Action
  def offered?(%{activity: activity, now: now}), do: ChangeAttendance.open?(activity, now)

  @impl Action
  def count(_ctx, checked),
    do: Enum.count(checked, &ChangeAttendance.changes?(:remove, &1.status))

  @impl Action
  def button_text(count),
    do: Format.count(count, one: "Remove 1 member", many: "Remove %d members")

  @impl Action
  def variant, do: :danger

  @impl Action
  def confirm(%{activity: activity}, checked) do
    members = checked |> length() |> Format.count(one: "1 member", many: "%d members")

    %{
      "data-confirm" =>
        "Remove #{members} from #{activity.title}? They come off its attendance. Add members can put them back, as attended with the activity's times."
    }
    |> put_hours(checked)
  end

  # "Casey Dhillon's 2h 30m go too." for each checked member who attended.
  defp put_hours(attrs, checked) do
    case Action.hours_text(checked) do
      nil -> attrs
      hours -> Map.put(attrs, "data-confirm-warning", "#{hours} go too.")
    end
  end

  @impl Action
  def run(_checked), do: {:in_place, :remove}
end
