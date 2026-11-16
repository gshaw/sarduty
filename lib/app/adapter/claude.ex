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
  """
  def create_message(body) when is_map(body) do
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
