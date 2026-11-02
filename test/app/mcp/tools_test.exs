defmodule App.MCP.ToolsTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.CheckReport
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

  test "an integer argument must be a whole number" do
    query = %{"query" => "select name from members"}
    assert Tools.check_arguments(CheckReport, query) == :ok
    assert Tools.check_arguments(CheckReport, Map.put(query, "report_id", 3)) == :ok

    assert {:error, "Give report_id as a number." <> _} =
             Tools.check_arguments(CheckReport, Map.put(query, "report_id", "3"))
  end

  test "the call log keeps only declared arguments, cut short" do
    args = %{"query" => String.duplicate("x", 5_000), "email" => "a@b.c"}
    logged = Tools.loggable_arguments(CheckReport, args)

    assert Map.keys(logged) == ["query"]
    assert String.length(logged["query"]) == 100
  end

  test "an argument that isn't a plain value is not logged as is" do
    assert Tools.loggable_arguments(CheckReport, %{"query" => %{"a" => 1}}) == %{
             "query" => "(not shown)"
           }

    assert Tools.loggable_arguments(CheckReport, "nope") == %{}
  end
end
