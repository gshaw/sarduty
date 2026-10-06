defmodule Web.ShortLinkLimit do
  @moduledoc """
  Caps short link codes that match nothing, per client IP. A code is about 40 bits, so
  with 20 misses every 10 minutes, sweeping for a live one would take far longer than
  any link stays open. Only misses count. Counters are in memory, so a deploy resets them.
  """

  alias App.RateLimit

  require Logger

  @limit 20
  @scale :timer.minutes(10)

  @doc "Whether this IP has used up its misses for now."
  def limited?(ip), do: ip |> key() |> RateLimit.get(@scale) >= @limit

  @doc "Counts a code that matched no live link, and logs when the IP reaches the limit."
  def miss(ip) do
    if ip |> key() |> RateLimit.inc(@scale) == @limit,
      do: Logger.warning("Short link limit reached: #{@limit} misses from #{ip}")

    :ok
  end

  defp key(ip), do: "short_link:#{RateLimit.ip_key(ip)}"
end
