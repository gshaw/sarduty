defmodule App.LineFormatter do
  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts
  @moduledoc """
  ExUnit's own formatter, with one line per test module in place of the dots. CI uses
  it: GitHub shows a log line only once it ends, so a row of dots shows no progress.
  Failure reports print as usual.
  """
  use GenServer

  alias ExUnit.CLIFormatter

  @impl GenServer
  def init(opts), do: CLIFormatter.init(opts)

  @impl GenServer
  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, _}}} = event, config),
    do: CLIFormatter.handle_cast(event, config)

  # A pass, skip or invalid test would print a dot, a * or a ?.
  def handle_cast({:test_finished, _} = event, config),
    do: silently(fn -> CLIFormatter.handle_cast(event, config) end)

  def handle_cast({:module_finished, %ExUnit.TestModule{} = module} = event, config) do
    module |> line() |> IO.puts()
    CLIFormatter.handle_cast(event, config)
  end

  def handle_cast(event, config), do: CLIFormatter.handle_cast(event, config)

  defp line(module) do
    tests = Enum.reject(module.tests, &match?({:excluded, _}, &1.state))

    failed =
      Enum.count(tests, &(match?({:failed, _}, &1.state) or match?({:invalid, _}, &1.state)))

    status = if failed > 0 or module.state != nil, do: "FAIL", else: "ok  "
    ms = tests |> Enum.map(& &1.time) |> Enum.sum() |> div(1000)

    counts =
      if failed > 0,
        do: "#{length(tests)} tests, #{failed} failed",
        else: "#{length(tests)} tests"

    "#{status} #{Path.relative_to_cwd(module.file)} (#{counts}, #{ms}ms)"
  end

  defp silently(fun) do
    {:ok, null} = StringIO.open("")
    leader = Process.group_leader()
    Process.group_leader(self(), null)

    try do
      fun.()
    after
      Process.group_leader(self(), leader)
      StringIO.close(null)
    end
  end
end
