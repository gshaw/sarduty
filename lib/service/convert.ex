defmodule Service.Convert do
  @moduledoc """
    Useful functions for converting data.
  """

  def duration_to_minutes(started_at, finished_at) do
    seconds = DateTime.diff(finished_at, started_at, :second)
    round(seconds / 60.0)
  end

  def duration_to_hours(started_at, finished_at) do
    seconds = DateTime.diff(finished_at, started_at, :second)
    Float.round(seconds / 3600.0, 1)
  end

  def duration_to_years(started_at, finished_at) do
    minutes = DateTime.diff(finished_at, started_at, :minute)
    Float.round(minutes / 525_600.0, 1)
  end
end
