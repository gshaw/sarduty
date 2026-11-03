defmodule App.Operation.CheckTravel do
  @moduledoc """
  A member checks the travel a team admin set for one of their attended rows (#230):
  That's right marks it checked, or they set it themselves, the same four ways as on
  Travel. Either way it counts as checked. Like the team admin's sets, it can't change
  once the activity is published.
  """

  alias App.Model.Activity
  alias App.Model.Member
  alias App.Model.Trip
  alias App.Operation.BuildMileageReport
  alias App.Operation.SetTravel

  @doc """
  `choice` is "right", or a travel with `km_text` for "other". Returns `{:ok, trip_or_plan}`
  or `{:error, reason}`: :published, :deleted, :not_set (no trip for the row), :no_route,
  or SetTravel's :bad_km and :bad_travel.
  """
  def call(
        team,
        %Activity{} = activity,
        %Member{} = member,
        user,
        d4h_attendance_id,
        choice,
        km_text,
        now
      ) do
    cond do
      activity.deleted_at -> {:error, :deleted}
      Activity.locked?(activity) -> {:error, :published}
      true -> check(team, activity, member, user, d4h_attendance_id, choice, km_text, now)
    end
  end

  defp check(team, activity, member, user, d4h_attendance_id, choice, km_text, now) do
    case Trip.for_member(activity, member)[d4h_attendance_id] do
      nil -> {:error, :not_set}
      trip when choice == "right" -> {:ok, Trip.check!(trip, now)}
      _trip -> change(team, activity, member, user, d4h_attendance_id, choice, km_text, now)
    end
  end

  defp change(team, activity, member, user, d4h_attendance_id, travel, km_text, now) do
    report = BuildMileageReport.call(team, activity, now, member: member)
    rows = Enum.filter(report.rows, &(&1.attendance.d4h_attendance_id == d4h_attendance_id))
    ids = Enum.map(rows, & &1.attendance.id)

    case SetTravel.plan(rows, ids, travel, km_text) do
      {:ok, %{sets: []}} ->
        {:error, :no_route}

      {:ok, plan} ->
        Trip.save_all!(activity, user, plan.sets, now, member.id)
        {:ok, plan}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Why the member's travel didn't save, for the toast."
  def error_text(_team, :not_set), do: "A team admin hasn't set this travel yet."

  def error_text(_team, :no_route),
    do: "No route from your home for that. Choose Other and type your km."

  def error_text(team, reason), do: SetTravel.error_text(team, reason)
end
