defmodule App.MCP.ToolsTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.ListActivities
  alias App.MCP.Tools

  test "every tool is read-only and has a unique name" do
    names = Enum.map(Tools.definitions(), & &1["name"])
    assert names == Enum.uniq(names)
    assert Enum.all?(Tools.definitions(), & &1["annotations"]["readOnlyHint"])
  end

  test "the call log keeps only declared arguments, cut short" do
    args = %{"from" => "2026-01-01", "tag" => String.duplicate("x", 500), "email" => "a@b.c"}
    logged = Tools.loggable_arguments(ListActivities, args)

    assert Map.keys(logged) == ["from", "tag"]
    assert String.length(logged["tag"]) == 100
  end

  test "an argument that isn't a plain value is not logged as is" do
    assert Tools.loggable_arguments(ListActivities, %{"tag" => %{"a" => 1}}) == %{
             "tag" => "(not shown)"
           }

    assert Tools.loggable_arguments(ListActivities, "nope") == %{}
  end
end
