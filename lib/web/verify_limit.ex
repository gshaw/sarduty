defmodule Web.VerifyLimit do
  @moduledoc """
  Caps failed card checks per client IP on the verify site, as a backstop: codes
  are too many to guess. Only misses count, so checking many real cards never trips it,
  and only for input that could be a code: anything else can't guess one. That matters
  at a command post, where everyone shares one IP and an app sees every barcode (#299).
  The pages, the photo routes, and the JSON check share one counter.
  """

  alias App.Model.Event
  alias App.RateLimit

  require Logger

  @limit 20
  @scale :timer.minutes(10)

  @doc "Whether this IP has used up its misses for now."
  def limited?(ip), do: ip |> key() |> RateLimit.get(@scale) >= @limit

  @doc "How long a limited IP waits at most, in seconds, for the 429's Retry-After."
  def retry_after, do: div(@scale, 1000)

  @doc """
  Counts a miss: a code or letter reference that matched nothing. `code` is the input as
  parsed, nil when it can't be one, which never counts. Logs and records when the IP
  reaches the limit.
  """
  def miss(_ip, nil), do: :ok

  def miss(ip, _code) do
    if ip |> key() |> RateLimit.inc(@scale) == @limit do
      Logger.warning("Verify limit reached: #{@limit} failed checks from #{ip}")
      Event.record!(:verify_limit_reached, ip: ip)
    end

    :ok
  end

  @doc """
  The client's IP. Behind Fly's proxy, `remote_ip` is Fly's, so read `Fly-Client-IP`;
  without it (dev, tests) use the peer address.
  """
  def client_ip(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, "fly-client-ip") do
      [ip | _] -> ip
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  # The LiveView's session, built from the page's HTTP request and signed into it. A
  # websocket can't see Fly-Client-IP (connect_info passes only x- headers), and Fly puts
  # its own address last in X-Forwarded-For, so the IP rides in from here.
  def session(conn), do: %{"client_ip" => client_ip(conn)}

  defp key(ip), do: "verify:#{RateLimit.ip_key(ip)}"
end
