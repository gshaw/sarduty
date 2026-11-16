defmodule App.AI.Tool do
  @moduledoc """
  A tool Claude may call during an AI writing ask (App.Operation.AskAI). It runs in SAR
  Duty, on the asker's team, and its answer goes back to Claude.

  The rules from MCP (#627, #816) hold, now that SAR Duty is the one sending: a tool only
  reads, and never answers with a member, an activity, a row, or a count from the team's
  records. A tool that runs a query runs it on Coast Range SAR, the made-up team. Each
  builds its answer from explicit maps; App.AI.ToolsTest checks the source.
  """

  alias App.Model.Team

  @type context :: %{team: Team.t(), now: DateTime.t()}

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback call(context(), args :: map()) :: {:ok, map()} | {:error, String.t()}

  @doc "The tool's definition, as the Messages API takes it."
  def definition(module),
    do: %{
      "name" => module.name(),
      "description" => module.description(),
      "input_schema" => module.input_schema()
    }
end
