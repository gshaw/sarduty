defmodule App.Operation.AskAITest do
  use ExUnit.Case, async: true

  alias App.AI.Job
  alias App.AI.Models
  alias App.AI.Tool.CheckReport
  alias App.Model.AISettings
  alias App.Operation.AskAI

  defp job do
    %Job{
      kind: :report,
      system: ["rules and language", "the team's names"],
      tools: [CheckReport],
      prompt: "The report as it stands",
      schema: %{"type" => "object"},
      finish: fn _output -> {:unchanged, ""} end,
      context: %{},
      ask: "hours this year"
    }
  end

  test "a request runs in the US, caches each system part, and lists the tools" do
    settings = %AISettings{report_model: "claude-sonnet-5-5"}
    messages = [%{"role" => "user", "content" => "hi"}]
    request = AskAI.request(settings, job(), messages)

    assert request["model"] == "claude-sonnet-5-5"
    assert request["inference_geo"] == "us"
    assert request["output_config"]["effort"] == "medium"
    assert request["output_config"]["format"]["type"] == "json_schema"
    assert Enum.map(request["tools"], & &1["name"]) == ["check_report"]
    assert request["messages"] == messages

    assert [
             %{"text" => "rules and language", "cache_control" => %{"type" => "ephemeral"}},
             %{"text" => "the team's names", "cache_control" => %{"type" => "ephemeral"}}
           ] = request["system"]

    refute Map.has_key?(request, "thinking")
    refute Map.has_key?(request, "temperature")
  end

  test "a form asks on the forms model, the rest on the reports model" do
    settings = %AISettings{report_model: "claude-sonnet-5-5", form_model: "claude-opus-5-5"}
    assert AskAI.request(settings, job(), [])["model"] == "claude-sonnet-5-5"
    assert AskAI.request(settings, %{job() | kind: :form}, [])["model"] == "claude-opus-5-5"

    assert AskAI.request(settings, %{job() | kind: :history_line}, [])["model"] ==
             "claude-sonnet-5-5"
  end

  test "with next asks on, the answer's schema asks for that many too" do
    settings = %AISettings{}
    schema = fn job -> AskAI.request(settings, job, [])["output_config"]["format"]["schema"] end

    refute Map.has_key?(schema.(job())["properties"] || %{}, "next")

    assert %{"properties" => %{"next" => %{"type" => "array"}}, "required" => ["next"]} =
             schema.(%{job() | next_asks: 3})

    assert schema.(%{job() | next_asks: 3})["properties"]["next"]["description"] =~ "Up to 3"
  end

  test "next asks are trimmed, blanks and long ones dropped, as many as the settings say" do
    long = String.duplicate("a", 81)

    assert AskAI.next(%{"next" => [" Group by quarter ", "", long, "A", "B", "C"]}, 2) ==
             ["Group by quarter", "A"]

    assert AskAI.next(%{"next" => ["A", "B", "C"]}, 4) == ["A", "B", "C"]
    assert AskAI.next(%{"note" => "no next"}, 2) == []
  end

  test "a response asks for tools, gives an answer, or ends the ask" do
    use = %{"type" => "tool_use", "id" => "t1", "name" => "check_report", "input" => %{}}

    assert {:tools, [^use]} =
             AskAI.next_step(%{
               "stop_reason" => "tool_use",
               "content" => [%{"type" => "thinking", "thinking" => ""}, use]
             })

    assert {:answer, %{"query" => "select name from members"}} =
             AskAI.next_step(%{
               "stop_reason" => "end_turn",
               "content" => [
                 %{"type" => "text", "text" => ~s({"query":"select name from members"})}
               ]
             })

    assert {:error, :failed} =
             AskAI.next_step(%{
               "stop_reason" => "end_turn",
               "content" => [%{"type" => "text", "text" => "not json"}]
             })

    assert {:error, :refused} = AskAI.next_step(%{"stop_reason" => "refusal", "content" => []})

    assert {:error, :too_long} =
             AskAI.next_step(%{"stop_reason" => "max_tokens", "content" => []})
  end

  test "usage reads every token count, and the cost comes from the model's price" do
    usage =
      AskAI.usage(%{
        "usage" => %{
          "input_tokens" => 1_000,
          "cache_creation_input_tokens" => 8_000,
          "cache_read_input_tokens" => 0,
          "output_tokens" => 2_000
        }
      })

    assert usage == %{input: 1_000, cache_write: 8_000, cache_read: 0, output: 2_000}
    # Sonnet 5.5: 1,000 × $2 + 8,000 × $2.50 + 2,000 × $10, per million tokens.
    assert Models.cost_microdollars("claude-sonnet-5-5", usage) == 42_000
    assert Models.cost_microdollars("claude-opus-5-5", usage) == 84_000
  end
end
