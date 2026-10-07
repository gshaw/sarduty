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
  """

  alias App.Model.Team

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback fields() :: [String.t()]
  @callback call(Team.t(), args :: map(), now :: DateTime.t()) ::
              {:ok, output :: map() | list(), row_count :: non_neg_integer()}
              | {:error, String.t()}
end
