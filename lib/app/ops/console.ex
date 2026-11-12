defmodule App.Ops.Console do
  @moduledoc """
  Records a shell before `bin/prod console` opens it: for a person, when no task does the
  job or the app is down. The repo's hook keeps agents out (docs/production.md). What's
  done in the shell isn't recorded, so say it on the issue.
  """

  use App.Ops.Task,
    name: "console",
    usage: "console",
    summary: "A shell on the machine, for people, when no task does it."

  @impl App.Ops.Task
  def run([]), do: {:ok, "Opening a shell. Say what you do in it on the issue."}
  def run(_args), do: {:error, "Usage: " <> usage()}
end
