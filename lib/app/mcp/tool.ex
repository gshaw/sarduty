defmodule App.MCP.Tool do
  @moduledoc """
  One MCP tool (#28). A tool is a module with this behaviour, listed in App.MCP.Tools.

  Tools only read (#627), and help an agent write reports (#816). An agent works from how
  the team is organized: the language, the fields, the team's names for things, and its
  reports' queries. No tool returns a member, an activity's title, a row, or a count from
  the team's records; a test seeds them and checks every tool's output.

  Each builds its output from explicit maps, never by encoding a struct, and `fields/0`
  lists every key its output may hold. `call/4` gets the team, the arguments, the time,
  and the agent's connection: its name, for a link that saves who wrote a report, and
  its user, whose editor follows a live draft (#834). It returns the output and how many
  items it holds, for the call log, or an error message for the agent.
  """

  alias App.Model.AgentConnection
  alias App.Model.Team

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback fields() :: [String.t()]
  @callback call(Team.t(), args :: map(), now :: DateTime.t(), connection :: %AgentConnection{}) ::
              {:ok, output :: map() | list(), row_count :: non_neg_integer()}
              | {:error, String.t()}
end
