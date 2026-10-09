defmodule Service.Convert do
  @moduledoc """
    Useful functions for converting data.
  """

  def duration_to_minutes(started_at, finished_at) do
    DateTime.diff(finished_at, started_at, :minute)
  end

  def duration_to_hours(started_at, finished_at) do
    minutes = duration_to_minutes(started_at, finished_at)
    Float.round(minutes / 60.0, 1)
  end

  def duration_to_months(started_at, finished_at) do
    days =
      finished_at
      |> DateTime.to_date()
      |> Date.diff(DateTime.to_date(started_at))

    round(days / 30.44)
  end

  @doc """
  A date and time on the wall clock in `timezone`, in UTC. A time a clock change skips
  is the time after the gap; one it repeats is the first.
  """
  def local_to_utc(%Date{} = date, %Time{} = time, timezone) do
    case DateTime.new(date, time, timezone) do
      {:ok, datetime} -> DateTime.shift_zone!(datetime, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
    end
  end

  @doc "A UTC time as `{date, time}` on the wall clock in `timezone`."
  def utc_to_local(%DateTime{} = datetime, timezone) do
    local = DateTime.shift_zone!(datetime, timezone)
    {DateTime.to_date(local), local |> DateTime.to_time() |> Time.truncate(:second)}
  end
end
