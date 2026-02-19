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
end
