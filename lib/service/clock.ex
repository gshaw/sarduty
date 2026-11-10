defmodule Service.Clock do
  @moduledoc """
  The time now, for code whose rules turn on the date: a year's tax credit letters wait
  for January 1, and close on August 1 (#995). It's DateTime.utc_now/0, except in a test
  that froze it with App.Clock.freeze/1: then that test's process and those it starts,
  such as a LiveView and the jobs Oban runs inline in it, see the frozen time.
  """

  @freezable Application.compile_env(:sarduty, :freezable_clock, false)

  @doc "Now, in UTC."
  def utc_now, do: (@freezable && frozen()) || DateTime.utc_now()

  # A test's frozen time, by its pid, from its own process or one it started.
  defp frozen do
    Enum.find_value([self() | Process.get(:"$callers", [])], fn pid ->
      case :ets.lookup(__MODULE__, pid) do
        [{^pid, now}] -> now
        [] -> nil
      end
    end)
  end
end
