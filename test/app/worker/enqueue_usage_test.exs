defmodule App.Worker.EnqueueUsageTest do
  use ExUnit.Case, async: true

  # Jobs go in through their worker's enqueue function, which builds the args from
  # structs (docs/jobs.md), so a job's args are written in one place. Building one
  # elsewhere, as `SomeWorker.new(…)` or an `Oban.insert` outside lib/app/worker/, fails
  # here.
  test "jobs are queued through their worker's enqueue" do
    hits =
      for path <- Path.wildcard("lib/**/*.ex"),
          {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          built_by_hand?(path, line),
          do: "#{path}:#{number}: #{String.trim(line)}"

    assert hits == [],
           "Queue these through the worker's enqueue function:\n" <> Enum.join(hits, "\n")
  end

  defp built_by_hand?(path, line) do
    Regex.match?(~r/\w+Worker\.new\(/, line) or
      (not String.starts_with?(path, "lib/app/worker/") and
         Regex.match?(~r/\bOban\.insert/, line))
  end
end
