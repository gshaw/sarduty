defmodule App.Adapter.Litestream do
  @moduledoc """
  Litestream's own metrics, on the same machine (`addr` in litestream.yml). Litestream
  runs the app as its child in production, so the port answers only there.
  """

  @doc """
  `{:ok, %{txid:, sync_errors:}}`: the newest transaction Litestream has seen, and its
  failed syncs since it started. `{:error, :unreachable}` where Litestream isn't running.
  """
  def fetch_metrics do
    url =
      Application.get_env(:sarduty, __MODULE__, [])[:metrics_url] ||
        "http://localhost:9090/metrics"

    case Req.get(url, [retry: false, receive_timeout: 2_000] ++ test_options()) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok,
         %{
           txid: metric(body, "litestream_txid"),
           sync_errors: metric(body, "litestream_sync_error_count")
         }}

      _ ->
        {:error, :unreachable}
    end
  end

  @doc "Pure. A gauge or counter's value in Prometheus text, summed over its labels, or nil."
  def metric(text, name) do
    values =
      for line <- String.split(text, "\n"),
          [_, value] <- [Regex.run(~r/^#{name}(?:\{[^}]*\})? (\S+)$/, line)],
          do: value |> Float.parse() |> elem(0) |> round()

    if values == [], do: nil, else: Enum.sum(values)
  end

  defp test_options, do: :sarduty |> Application.get_env(__MODULE__, []) |> Keyword.take([:plug])
end
