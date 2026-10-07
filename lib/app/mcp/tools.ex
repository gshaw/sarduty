defmodule App.MCP.Tools do
  @moduledoc """
  The MCP tools the endpoint offers (#28). Adding a tool is a module with the
  App.MCP.Tool behaviour and a line here.
  """

  @tools [
    App.MCP.Tool.GetTeam,
    App.MCP.Tool.ListMembers,
    App.MCP.Tool.AttendanceSummary,
    App.MCP.Tool.ListActivities,
    App.MCP.Tool.ListQualifications
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
        "annotations" => %{"readOnlyHint" => true, "openWorldHint" => false}
      }
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
