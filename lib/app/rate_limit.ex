defmodule App.RateLimit do
  @moduledoc """
  Hammer's in-memory counters. Production is one Fly machine, so ETS is enough.
  """

  use Hammer, backend: :ets

  @doc """
  The part of a client IP that per-IP limits count against. An IPv4 address counts on
  its own. An IPv6 address counts by its /64, since anyone on IPv6 gets a whole /64 and
  could step through it to dodge a per-address cap (#176). Anything else, like a test's
  made-up IP, is used as is.
  """
  def ip_key(ip) when is_binary(ip) do
    case ip |> String.to_charlist() |> :inet.parse_address() do
      {:ok, {a, b, c, d, _e, _f, _g, _h}} -> prefix_64(a, b, c, d)
      _ipv4_or_other -> ip
    end
  end

  defp prefix_64(a, b, c, d) do
    {a, b, c, d, 0, 0, 0, 0} |> :inet.ntoa() |> to_string() |> Kernel.<>("/64")
  end
end
