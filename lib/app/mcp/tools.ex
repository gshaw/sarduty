defmodule App.MCP.Tools do
  @moduledoc """
  The MCP tools the endpoint offers (#28). Adding a tool is a module with the
  App.MCP.Tool behaviour and a line here.
  """

  @tools [
    App.MCP.Tool.GetTeam,
    App.MCP.Tool.NeedsAttention,
    App.MCP.Tool.ListMembers,
    App.MCP.Tool.AttendanceSummary,
    App.MCP.Tool.TaxCreditHours,
    App.MCP.Tool.ListActivities,
    App.MCP.Tool.ListAttendance,
    App.MCP.Tool.ListQualifications,
    App.MCP.Tool.ListChores,
    App.MCP.Tool.MemberHistory,
    App.MCP.Tool.ActivityHistory
  ]

  def all, do: @tools

  @doc "The tool with this name, or nil."
  def find(name) when is_binary(name), do: Enum.find(@tools, &(&1.name() == name))
  def find(_name), do: nil

  @doc "What `tools/list` returns for each tool."
  def definitions do
    Enum.map(@tools, fn tool ->
      %{
        "name" => tool.name(),
        "description" => tool.description(),
        "inputSchema" => tool.input_schema(),
        "annotations" => %{
          "readOnlyHint" => true,
          "destructiveHint" => false,
          "openWorldHint" => false
        }
      }
    end)
  end

  @doc """
  `:ok`, or `{:error, message}` when an argument the tool's input schema calls an
  integer is not a whole number, or is required and missing. Ids come from agents, and
  a nil or a string one raised in the tool (2026-10-28). A string such as D4H's "02241"
  is refused, not read as 2241. Tools check dates and the rest themselves.
  """
  def check_arguments(tool, args) do
    schema = tool.input_schema()
    required = Map.get(schema, "required", [])

    schema
    |> Map.get("properties", %{})
    |> Enum.filter(fn {_key, property} -> property["type"] == "integer" end)
    |> Enum.sort()
    |> Enum.find_value(:ok, fn {key, property} ->
      value = Map.get(args, key)

      cond do
        is_integer(value) -> nil
        value == nil and key not in required -> nil
        true -> {:error, "Give #{key} as a number. #{property["description"]}."}
      end
    end)
  end

  @doc """
  The arguments a tool's input schema declares, for the call log. Anything else the
  agent sent is dropped, and long strings are cut.
  """
  def loggable_arguments(tool, args) when is_map(args) do
    known = tool.input_schema() |> Map.get("properties", %{}) |> Map.keys()

    args
    |> Map.take(known)
    |> Map.new(fn
      {key, value} when is_binary(value) -> {key, String.slice(value, 0, 100)}
      {key, value} when is_number(value) or is_boolean(value) or is_nil(value) -> {key, value}
      {key, _other} -> {key, "(not shown)"}
    end)
  end

  def loggable_arguments(_tool, _args), do: %{}
end
