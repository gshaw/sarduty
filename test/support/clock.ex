defmodule App.Clock do
  @moduledoc """
  Freezes Service.Clock for the test that calls `freeze/1`, until it ends: for code
  whose rules turn on the date, such as a year's tax credit letters closing on August 1.
  """

  @doc "Makes Service.Clock.utc_now/0 return `now` in this test, and what it starts."
  def freeze(%DateTime{} = now) do
    # Microsecond precision, as DateTime.utc_now/0's, which Ecto's usec fields want.
    {microsecond, _precision} = now.microsecond
    now = %{now | microsecond: {microsecond, 6}}
    pid = self()
    :ets.insert(Service.Clock, {pid, now})
    ExUnit.Callbacks.on_exit(fn -> :ets.delete(Service.Clock, pid) end)
    now
  end
end
