defmodule Web.RequestLog do
  @moduledoc """
  Logs each request as Phoenix would, `GET /path` then `Sent 200 in 3ms`, but with
  secrets cut out of the path: attendance tokens, short link codes, and card codes
  (#176). Phoenix's own request lines are off (`log: false` in the endpoint), since
  they print the whole path. Web.HoneybadgerFilter uses filter_path/2 too.
  """

  require Logger

  @filtered "[FILTERED]"

  # The verify site's paths that aren't a card code.
  @verify_paths ["o", "live" | Web.static_paths()]

  def attach do
    :telemetry.attach_many(
      "sarduty-request-log",
      [[:phoenix, :endpoint, :start], [:phoenix, :endpoint, :stop]],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:phoenix, :endpoint, :start], _measurements, %{conn: conn}, _config) do
    Logger.info(fn -> [conn.method, ?\s, filter_path(conn.host, conn.request_path)] end)
  end

  def handle_event([:phoenix, :endpoint, :stop], %{duration: duration}, %{conn: conn}, _config) do
    Logger.info(fn ->
      ms = System.convert_time_unit(duration, :native, :microsecond) / 1000
      type = if conn.state == :set_chunked, do: "Chunked", else: "Sent"
      "#{type} #{conn.status} in #{:erlang.float_to_binary(ms, decimals: 1)}ms"
    end)
  end

  @doc """
  The path with any token or code in it replaced by `[FILTERED]`. `host` tells the
  verify site, where a bare `/K7Q4M2XA` is a card code, from the app.
  """
  def filter_path(host, path) when is_binary(path) do
    host |> verify_host?() |> filter_segments(String.split(path, "/")) |> Enum.join("/")
  end

  def filter_path(_host, path), do: path

  defp verify_host?(host), do: is_binary(host) and String.starts_with?(host, "verify.")

  defp filter_segments(true, ["", code | rest]) when code != "" and code not in @verify_paths,
    do: ["", @filtered | rest]

  defp filter_segments(_verify?, ["", "attendance", _token | rest]),
    do: ["", "attendance", @filtered | rest]

  defp filter_segments(_verify?, ["", "s", _code | rest]), do: ["", "s", @filtered | rest]

  defp filter_segments(_verify?, ["", verify, _code | rest]) when verify in ["verify", "VERIFY"],
    do: ["", verify, @filtered | rest]

  defp filter_segments(_verify?, segments), do: segments
end
