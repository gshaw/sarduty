defmodule App.MCP.ToolsTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.ListActivities
  alias App.MCP.Tools

  test "every tool has a unique name, and only the proposing tool writes" do
    names = Enum.map(Tools.definitions(), & &1["name"])
    assert names == Enum.uniq(names)

    writes = for t <- Tools.definitions(), !t["annotations"]["readOnlyHint"], do: t["name"]
    assert writes == ["propose_attendance_changes"]
  end

  # An agent may propose a change set, never apply one (#216).
  test "no tool applies a change set" do
    for path <- Path.wildcard("lib/app/mcp/**/*.ex") do
      source = File.read!(path)
      refute source =~ "ApplyChangeSet", "#{path} mentions ApplyChangeSet"
      refute source =~ "ApplyProposedChangeSet", "#{path} mentions ApplyProposedChangeSet"
      refute source =~ "Adapter.D4H", "#{path} mentions the D4H adapter"
    end
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
