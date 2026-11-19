defmodule App.AI.HistoryLineJobTest do
  use ExUnit.Case, async: true

  alias App.AI.HistoryLineJob
  alias App.Model.AISettings
  alias App.Operation.AskAI

  @before %{name: "Members", about: nil, query: "select name from members"}
  @saved %{name: "Members", about: nil, query: "select name, standing from members"}

  test "the request is small: both versions, no tools, low effort" do
    job = HistoryLineJob.build(@before, @saved)
    request = AskAI.request(%AISettings{}, job, [])

    assert job.kind == :history_line
    assert job.ask == "Members"
    assert job.prompt =~ "Before:\nName: Members"
    assert job.prompt =~ "select name, standing from members"
    assert request["output_config"]["effort"] == "low"
    refute Map.has_key?(request, "tools")
  end

  test "the line is cut to What changed's length, and none changes nothing" do
    long = String.duplicate("a", 150)
    assert {:ok, %{line: line}} = HistoryLineJob.finish(%{"line" => long})
    assert String.length(line) == 100
    assert {:unchanged, ""} = HistoryLineJob.finish(%{"line" => " "})
  end
end
