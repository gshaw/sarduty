defmodule Service.Convert do
  @moduledoc """
    Useful functions for converting data.
  """

  def duration_to_hours(started_at, finished_at) do
    minutes = DateTime.diff(finished_at, started_at, :minute)
    Float.round(minutes / 60.0, 1)
  end
end
