defmodule App.MCP.Tool do
  @moduledoc """
  One MCP tool (#28). A tool is a module with this behaviour, listed in App.MCP.Tools.

  Tools only read. Each builds its output from explicit maps, never by encoding a
  struct, and `fields/0` lists every key its output may hold. A test checks the output
  against that list, so a new field is added on purpose. No tool returns email, phone,
  an address, coordinates, letter text, or a key.

  `call/3` loads with the team's id on every query, joins included, then hands the rows
  to a pure function that builds the output. It returns the output and how many rows it
  holds, for the call log, or an error message for the agent.

  A tool that proposes a change set (#216) implements `call_as/4` instead, which also
  gets the token's user, and `read_only?/0` returning false. It saves a change set that
  waits for a team admin. No tool applies one or calls D4H.
  """

  alias App.Accounts.User
  alias App.Model.Team

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback fields() :: [String.t()]
  @callback call(Team.t(), args :: map(), now :: DateTime.t()) ::
              {:ok, output :: map() | list(), row_count :: non_neg_integer()}
              | {:error, String.t()}
  @callback call_as(Team.t(), User.t(), args :: map(), now :: DateTime.t()) ::
              {:ok, output :: map() | list(), row_count :: non_neg_integer()}
              | {:error, String.t()}
  @callback read_only?() :: boolean()

  @optional_callbacks call: 3, call_as: 4, read_only?: 0

  @doc "Runs `tool` for the token's team and user."
  def run(tool, %Team{} = team, %User{} = user, args, now) do
    Code.ensure_loaded!(tool)

    if function_exported?(tool, :call_as, 4),
      do: tool.call_as(team, user, args, now),
      else: tool.call(team, args, now)
  end

  @doc "Whether the tool only reads. A tool says otherwise with `read_only?/0`."
  def read_only?(tool) do
    Code.ensure_loaded!(tool)
    if function_exported?(tool, :read_only?, 0), do: tool.read_only?(), else: true
  end
end
