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

  @impl Web.ActivityMembersLive.Action
  def value, do: "remove"

  @impl Web.ActivityMembersLive.Action
  def label, do: "Remove from the activity"

  @impl Web.ActivityMembersLive.Action
  def hint(_ctx), do: "Add members puts them back, as attended."

  @impl Web.ActivityMembersLive.Action
  def offered?(%{activity: activity, now: now}), do: ChangeAttendance.open?(activity, now)

  @impl Web.ActivityMembersLive.Action
  def count(checked), do: Enum.count(checked, &ChangeAttendance.changes?(:remove, &1.status))

  @impl Web.ActivityMembersLive.Action
  def button(count), do: Format.count(count, one: "Remove 1 member", many: "Remove %d members")

  @impl Web.ActivityMembersLive.Action
  def variant, do: :danger

  @impl Web.ActivityMembersLive.Action
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
    case for row <- checked, row.status == "attending", do: row do
      [] ->
        attrs

      attended ->
        hours =
          attended
          |> Enum.sort_by(&String.downcase(&1.member.name))
          |> Enum.map(&"#{&1.member.name}'s #{Format.duration(&1.duration_in_minutes || 0)}")
          |> Format.and_list()

        Map.put(attrs, "data-confirm-warning", "#{hours} go too.")
    end
  end

  @impl Web.ActivityMembersLive.Action
  def run, do: {:in_place, :remove}
end
