defmodule App.Adapter.ClaudeTest do
  use ExUnit.Case, async: true

  alias App.Adapter.Claude

  # A form's first draft streams under the hood (#1089), and comes back as the response a
  # request without streaming gets.
  @stream """
  event: message_start
  data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":900,"cache_read_input_tokens":20000,"output_tokens":1}}}

  event: content_block_start
  data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

  event: content_block_delta
  data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Read the "}}

  event: content_block_delta
  data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"page."}}

  event: content_block_delta
  data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig"}}

  event: content_block_stop
  data: {"type":"content_block_stop","index":0}

  event: ping
  data: {"type":"ping"}

  event: content_block_start
  data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"call_1","name":"check_form","input":{}}}

  event: content_block_delta
  data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"text\\": \\"form "}}

  event: content_block_delta
  data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"'Debrief'\\"}"}}

  event: content_block_stop
  data: {"type":"content_block_stop","index":1}

  event: message_delta
  data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":420}}

  event: message_stop
  data: {"type":"message_stop"}

  """

  test "a stream's pieces become one message" do
    assert {:ok, message} = Claude.assemble(@stream)

    assert message["stop_reason"] == "tool_use"

    assert message["usage"] == %{
             "input_tokens" => 900,
             "cache_read_input_tokens" => 20_000,
             "output_tokens" => 420
           }

    assert [
             %{"type" => "thinking", "thinking" => "Read the page.", "signature" => "sig"},
             %{
               "type" => "tool_use",
               "id" => "call_1",
               "name" => "check_form",
               "input" => %{"text" => "form 'Debrief'"}
             }
           ] = message["content"]
  end

  test "a stream that ends in an error gives the error" do
    stream = """
    event: message_start
    data: {"type":"message_start","message":{"content":[],"usage":{"input_tokens":9}}}

    event: error
    data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}

    """

    assert {:error, %{"type" => "overloaded_error"}} = Claude.assemble(stream)
  end

  test "a streamed request sends stream, and a busy stream is busy" do
    test = self()

    Req.Test.stub(Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:sent, Jason.decode!(body)})

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, """
      event: error
      data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}

      """)
    end)

    assert {:error, :busy} = Claude.create_message(%{"model" => "m"}, stream: true)
    assert_received {:sent, %{"stream" => true}}
  end
end
