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
  alias Web.Components.Messages

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
    count = length(checked)
    members = Format.count(count, one: "1 member", many: "%d members")

    %{
      "data-confirm" =>
        "Remove #{members} from #{activity.title}? They come off its attendance. Add members can put them back, as attended with the activity's times."
    }
    |> put_hours(checked)
    |> Map.merge(Messages.confirm_check(count, "I understand #{members} come off the activity."))
  end

  # "Casey Dhillon's 2h 30m go too.", or from 4 who attended "6 who attended lose 30 hours too."
  defp put_hours(attrs, checked) do
    case Action.hours_lost(checked, true) do
      nil -> attrs
      line -> Map.put(attrs, "data-confirm-warning", line)
    end
  end

  @impl Action
  def run(_checked), do: {:in_place, :remove}
end
