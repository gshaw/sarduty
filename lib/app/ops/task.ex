defmodule App.Ops.Task do
  @moduledoc """
  A task `bin/prod` runs in production (docs/production.md). `use App.Ops.Task` with
  its `name`, its `usage` line, a one-line `summary` for `bin/prod list`, and
  `write: true` when it changes data, then define `run/1`, which gets the arguments
  after the task's name as strings.

  A task never reads or prints a secret, and prints the fewest fields that answer the
  question. `run/1` returns `{:ok, %{columns: [...], rows: [[...]]}}` for a table, with
  an optional `note:` line under it, `{:ok, line}` for one line, or `{:error, line}`.
  """

  @type output :: %{columns: [String.t()], rows: [list()]} | String.t()

  @callback run([String.t()]) :: {:ok, output()} | {:error, String.t()}

  defmacro __using__(opts) do
    quote do
      @behaviour App.Ops.Task

      def name, do: unquote(Keyword.fetch!(opts, :name))
      def usage, do: unquote(Keyword.fetch!(opts, :usage))
      def summary, do: unquote(Keyword.fetch!(opts, :summary))
      def write?, do: unquote(Keyword.get(opts, :write, false))
    end
  end
end
