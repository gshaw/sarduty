defmodule App.MCP.ToolsTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.ListActivities
  alias App.MCP.Tools

  test "every tool has a unique name" do
    names = Enum.map(Tools.definitions(), & &1["name"])
    assert names == Enum.uniq(names)
  end

  # Tools only read (#627): no change set, no write, no D4H.
  test "no tool writes" do
    for path <- Path.wildcard("lib/app/mcp/**/*.ex") do
      source = File.read!(path)
      refute source =~ "ChangeSet", "#{path} mentions ChangeSet"
      refute source =~ "Repo.insert", "#{path} inserts"
      refute source =~ "Repo.update", "#{path} updates"
      refute source =~ "Repo.delete", "#{path} deletes"
      refute source =~ "Adapter.D4H", "#{path} mentions the D4H adapter"
      refute source =~ "SendChores", "#{path} mentions SendChores"
      refute source =~ "SaveChore.", "#{path} mentions SaveChore"
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
