defmodule App.AI.ToolsTest do
  use ExUnit.Case, async: true

  # The rules from MCP (#627, #816), which AI writing replaced (#1087): AI writing reads
  # only, and never runs a query on the team's own records. App.AI.ToolTest checks what
  # the tools answer.
  @paths ["lib/app/operation/ask_ai.ex" | Path.wildcard("lib/app/ai/**/*.ex")]

  test "nothing in AI writing writes, but the ask's own row" do
    for path <- @paths do
      source = File.read!(path)
      refute source =~ "ChangeSet", "#{path} mentions ChangeSet"
      refute source =~ "Repo.insert", "#{path} inserts"
      refute source =~ "Repo.update", "#{path} updates"
      refute source =~ "Repo.delete", "#{path} deletes"
      refute source =~ "Adapter.D4H", "#{path} mentions the D4H adapter"
    end
  end

  # A reply that depended on the team's rows would let Claude learn about the team, one
  # yes-or-no question per call (#834).
  test "nothing in AI writing runs a query on the team's records" do
    for path <- @paths do
      source = File.read!(path)
      refute source =~ ~r/Report\.run\(/, "#{path} runs a report"
      refute source =~ "Report.page", "#{path} runs a report's page"
      refute source =~ "Report.ids", "#{path} runs a report for its ids"
      refute source =~ "Runner", "#{path} mentions the runner"
    end
  end

  test "there are AI writing files to check" do
    assert length(@paths) >= 6
  end
end
