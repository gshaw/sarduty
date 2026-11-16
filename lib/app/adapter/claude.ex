defmodule App.Adapter.Claude do
  @moduledoc """
  The Claude API, for AI writing (docs/ai-writing.md). The only module that knows the
  API's address, headers, and errors. Optional: without ANTHROPIC_API_KEY, AI writing is
  off and its box never shows. Tests send every request to `Req.Test`.

  The key is from SAR Duty's own workspace in the Console org linked to Gerry's Max plan,
  so asks spend that plan's monthly API credit. With no credit bought and no auto-reload,
  the API refuses once the credit is spent: `{:error, :no_credit}`.
  """

  require Logger

  @host "https://api.anthropic.com"
  @version "2026-10-21"
  @timeout_ms 120_000

  @doc "Whether the key is set, so AI writing can run here."
  def configured?, do: api_key() not in [nil, ""]

  @doc """
  Sends one Messages API request: `body` is the request as a map. `{:ok, response}` with
  the response's JSON as a map, `{:error, :no_credit}` when the credit is spent,
  `{:error, :busy}` for a rate limit or an overloaded API, or `{:error, :unreachable}`.
  `stream: true` streams it under the hood and gives the same answer.
  """
  def create_message(body, opts \\ []) when is_map(body) do
    body = if opts[:stream], do: Map.put(body, "stream", true), else: body

    response =
      [
        base_url: @host,
        url: "/v1/messages",
        method: :post,
        headers: [
          {"x-api-key", api_key()},
          {"anthropic-version", @version}
        ],
        json: body,
        receive_timeout: @timeout_ms,
        retry: :transient,
        max_retries: 2
      ]
      |> Keyword.merge(Keyword.take(config(), [:plug, :retry]))
      |> Req.request()

    case response do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        streamed(body)

      {:ok, %{status: status, body: body}} ->
        error(status, body)

      {:error, exception} ->
        Logger.warning("Claude API unreachable: #{Exception.message(exception)}")
        {:error, :unreachable}
    end
  end

  @doc "One tiny request to `model`, for Adminland's test: `:ok` or `{:error, reason}`."
  def check(model) do
    body = %{
      "model" => model,
      "max_tokens" => 64,
      "inference_geo" => "us",
      "output_config" => %{"effort" => "low"},
      "messages" => [%{"role" => "user", "content" => "Reply with the word OK."}]
    }

    case create_message(body) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp streamed(body) do
    case assemble(body) do
      {:ok, message} -> {:ok, message}
      {:error, error} -> error(200, %{"error" => error})
    end
  end

  @doc """
  A streamed response's events, as the API sends them, put back into one message:
  `{:ok, message}`, or `{:error, error}` with the API's error when the stream ends in
  one. Text, thinking and its signature, and a tool call's input come in pieces.
  """
  def assemble(events) when is_binary(events) do
    events
    |> String.split(~r/\r?\n\r?\n/)
    |> Enum.flat_map(&event_data/1)
    |> Enum.reduce_while({%{"content" => []}, %{}}, &apply_event/2)
    |> case do
      {:error, error} -> {:error, error}
      {message, _partial} -> {:ok, Map.update!(message, "content", &Enum.reverse/1)}
    end
  end

  defp event_data(event) do
    data =
      for "data:" <> rest <- String.split(event, ~r/\r?\n/), do: String.trim_leading(rest)

    case Jason.decode(Enum.join(data, "\n")) do
      {:ok, %{"type" => _type} = decoded} -> [decoded]
      _not_data -> []
    end
  end

  # The content is kept newest first while it streams; `partial` holds each tool call's
  # input as text until its block stops.
  defp apply_event(%{"type" => "message_start", "message" => start}, {_message, partial}),
    do: {:cont, {Map.put(start, "content", []), partial}}

  defp apply_event(%{"type" => "content_block_start", "content_block" => block}, {message, p}),
    do: {:cont, {Map.update!(message, "content", &[block | &1]), p}}

  defp apply_event(%{"type" => "content_block_delta", "index" => i, "delta" => delta}, acc),
    do: {:cont, delta(acc, i, delta)}

  defp apply_event(%{"type" => "content_block_stop", "index" => i}, {message, partial}) do
    case Map.pop(partial, i) do
      {nil, partial} ->
        {:cont, {message, partial}}

      {json, partial} ->
        input = if json == "", do: %{}, else: Jason.decode!(json)
        {:cont, {update_last(message, &Map.put(&1, "input", input)), partial}}
    end
  end

  defp apply_event(%{"type" => "message_delta"} = event, {message, partial}) do
    message =
      message
      |> Map.merge(event["delta"] || %{})
      |> Map.update("usage", event["usage"] || %{}, &Map.merge(&1, event["usage"] || %{}))

    {:cont, {message, partial}}
  end

  defp apply_event(%{"type" => "error", "error" => error}, _acc), do: {:halt, {:error, error}}
  defp apply_event(_ping_or_stop, acc), do: {:cont, acc}

  # Blocks stream one at a time, so a delta is always for the newest block.
  defp delta({message, partial}, i, %{"type" => "input_json_delta", "partial_json" => json}),
    do: {message, Map.update(partial, i, json, &(&1 <> json))}

  defp delta({message, partial}, _i, %{"type" => type} = delta) do
    key =
      case type do
        "text_delta" -> "text"
        "thinking_delta" -> "thinking"
        "signature_delta" -> "signature"
        _other -> nil
      end

    if key,
      do:
        {update_last(
           message,
           &Map.update(&1, key, delta[key], fn text -> text <> delta[key] end)
         ), partial},
      else: {message, partial}
  end

  defp update_last(%{"content" => [block | rest]} = message, fun),
    do: %{message | "content" => [fun.(block) | rest]}

  defp update_last(message, _fun), do: message

  # A spent credit is a 400 whose message names the credit balance. Only the error's type
  # and message are logged: the body never repeats the request.
  defp error(status, body) do
    {type, message} = error_text(body)
    Logger.warning("Claude API #{status}: #{type} #{message}")

    cond do
      status == 400 and message =~ ~r/credit balance/i -> {:error, :no_credit}
      status in [429, 529] or type == "overloaded_error" -> {:error, :busy}
      true -> {:error, :unreachable}
    end
  end

  defp error_text(%{"error" => %{"type" => type, "message" => message}}), do: {type, message}
  defp error_text(_body), do: {"unknown", ""}

  defp api_key, do: config()[:api_key]
  defp config, do: Application.get_env(:sarduty, __MODULE__, [])
end
