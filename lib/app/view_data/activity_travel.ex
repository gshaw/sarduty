defmodule App.ViewData.ActivityTravel do
  @moduledoc """
  An activity's Travel page (#230): each attended row's round trips from the mileage
  report, with the trip a team admin set for it, if any. Rows not set come first.

  d4h_prompt/3 writes the text a browser agent such as Claude in Chrome reads to type
  the km into D4H's mileage page, from what's saved: D4H's API has no mileage.
  Written by Andrew Wallwork for South Fraser SAR, then moved onto saved trips.
  """
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Trip
  alias App.Operation.BuildMileageReport
  alias App.Repo
  alias Service.Format

  @doc """
  The page's rows: the mileage report's, each with `trip` (a `Trip`, or nil), split into
  `not_set` and `set`, in the report's order.
  """
  def load(team, %Activity{} = activity, now) do
    report = BuildMileageReport.call(team, activity, now)
    build(report, Trip.by_attendance(activity))
  end

  @doc "The page from the mileage report and the trips by D4H attendance id. Pure."
  def build(report, trips) do
    rows = Enum.map(report.rows, &Map.put(&1, :trip, trips[&1.attendance.d4h_attendance_id]))
    {set, not_set} = Enum.split_with(rows, & &1.trip)
    %{rows: rows, set: set, not_set: not_set, yard_to_activity_km: report.yard_to_activity_km}
  end

  @doc """
  The activity's attended rows, how many have no trip yet, and how many members haven't
  checked a trip set for them, for its Actions link and Change activity: `%{rows: 10,
  not_set: 2, unchecked: 3}`. Reads no Mapbox.
  """
  def counts(%Activity{} = activity, now) do
    Attendance
    |> Attendance.attended(now)
    |> where([r], r.activity_id == ^activity.id)
    |> join(:inner, [r], m in assoc(r, :member), as: :member)
    |> where([member: m], m.team_id == ^activity.team_id)
    |> join(:left, [r], t in Trip,
      on: t.activity_id == r.activity_id and t.d4h_attendance_id == r.d4h_attendance_id,
      as: :trip
    )
    |> select([r, trip: t], %{
      rows: count(r.id),
      not_set: count(r.id) - count(t.id),
      unchecked:
        count(
          fragment(
            "DISTINCT CASE WHEN ? IS NOT NULL AND ? IS NULL THEN ? END",
            t.id,
            t.checked_at,
            r.member_id
          )
        )
    })
    |> Repo.one()
  end

  @doc "How a trip got there, in the page's words."
  def travel_text("icp"), do: "Drove to the ICP"
  def travel_text("yard"), do: "Drove to the yard"
  def travel_text("passenger"), do: "Passenger"
  def travel_text("other"), do: "Other"

  @doc ~s(A trip in a sentence: "drove to the ICP, 62 km there and back from home".)
  def trip_text(%{travel: "icp", km: km}),
    do: "drove to the ICP, #{Format.km(km)} there and back from home"

  def trip_text(%{travel: "yard", km: km}),
    do: "drove to the yard, #{Format.km(km)} there and back from home"

  def trip_text(%{travel: "passenger"}), do: "a passenger, #{Format.km(0)}"
  def trip_text(%{travel: "other", km: km}), do: "#{Format.km(km)} there and back"

  @doc """
  What to paste into a browser agent with D4H's mileage page open: the activity by its
  reference and link, how to fill each km box without saving, then one line per row set
  (name, attendance times, km) and the rows to leave alone. Times are in the team's
  zone, as D4H shows them.
  """
  def d4h_prompt(view, team, %Activity{} = activity) do
    lines = Enum.map(view.set, &"#{row_text(&1, team.timezone)} | #{&1.trip.km}")

    leave_alone =
      case Enum.map(view.not_set, &row_text(&1, team.timezone)) do
        [] -> []
        rows -> ["", "Leave the Mileage km box alone on these rows:" | rows]
      end

    Enum.join(steps(team, activity) ++ lines ++ leave_alone, "\n")
  end

  defp steps(team, activity) do
    service = D4H.service_name(team)

    [
      "Fill in mileage in #{service} for activity #{activity.ref_id}, \"#{activity.title}\":",
      D4H.activity_url(team, activity),
      "",
      "Open that activity's mileage page in this tab. It lists each attendance row with a " <>
        "Name, the attendance times under it, and Per Attendance, Meals, and Mileage boxes. " <>
        "Mileage has a rate box, then \"x\", then a km box. Check the page names activity " <>
        "#{activity.ref_id} before you change anything.",
      "",
      "For each line below:",
      "1. Find the row with this name and these attendance times. #{service} may show a " <>
        "role in brackets after the name, such as (Team Member).",
      "2. Clear the Mileage km box (the box after \"x\") and type the km.",
      "",
      "Don't change the rate, Per Attendance, or Meals boxes. Don't change any row that " <>
        "isn't listed. Don't save. When you finish, tell me which lines you filled and any " <>
        "line whose row you couldn't find, so I can check and save.",
      "",
      "Name | Attendance | km"
    ]
  end

  defp row_text(row, timezone), do: "#{row.member.name} | #{times(row.attendance, timezone)}"

  @doc ~s(An attendance row's times, as D4H shows them: "Oct 30, 14:00 to Oct 30, 18:30".)
  def times(%{started_at: nil}, _timezone), do: "Times not known"

  def times(%{started_at: started_at, finished_at: nil}, timezone),
    do: "From " <> Format.month_day_time(started_at, timezone)

  def times(%{started_at: started_at, finished_at: finished_at}, timezone),
    do:
      "#{Format.month_day_time(started_at, timezone)} to #{Format.month_day_time(finished_at, timezone)}"
end
