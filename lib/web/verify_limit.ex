defmodule Web.VerifyLimit do
  @moduledoc """
  Caps failed card checks per client IP on the verify site, as a backstop: codes
  are too many to guess. Only misses count, so checking many real cards never trips it,
  and only for input that could be a code: anything else can't guess one. That matters
  at a command post, where everyone shares one IP and an app sees every barcode (#299).
  The pages, the photo routes, and the JSON check share one counter.

  Misses across every IP are counted too, as an alarm and never a block: a cap on the
  whole site would let anyone stop every card check by sending junk. Past the alarm's
  count, a real card found from an IP that has missed is recorded, so a guess that
  worked names the card to replace. docs/member-cards.md has what to do.
  """

  alias App.Model.Event
  alias App.Model.MemberCard
  alias App.RateLimit

  require Logger

  @limit 20
  @scale :timer.minutes(10)

  @site_key "verify:site"
  @site_limit 500
  @site_scale :timer.hours(1)

  @doc "Whether this IP has used up its misses for now."
  def limited?(ip), do: ip |> key() |> RateLimit.get(@scale) >= @limit

  @doc "How long a limited IP waits at most, in seconds, for the 429's Retry-After."
  def retry_after, do: div(@scale, 1000)

  @doc """
  Counts a miss: a code or letter reference that matched nothing. `code` is the input as
  parsed, nil when it can't be one, which never counts. Logs and records when the IP
  reaches the limit, and when the whole site reaches the alarm's count.
  """
  def miss(_ip, nil), do: :ok

  def miss(ip, _code) do
    if ip |> key() |> RateLimit.inc(@scale) == @limit do
      Logger.warning("Verify limit reached: #{@limit} failed checks from #{ip}")
      Event.record!(:verify_limit_reached, ip: ip)
    end

    if RateLimit.inc(@site_key, @site_scale) == @site_limit, do: alarm()

    :ok
  end

  @doc """
  Notes a real card found, the sample cards aside. While the alarm is up, a card found
  from an IP that has missed is recorded with the card's id: it may be a guess that worked.
  """
  def hit(ip, %MemberCard{} = card) do
    if alarm?() and ip |> key() |> RateLimit.get(@scale) > 0 do
      Event.record!(:verify_guess_found,
        ip: ip,
        team_id: card.member.team_id,
        data: %{member_card_id: card.id}
      )
    end

    :ok
  end

  @doc "Whether misses across the site have reached the alarm's count this hour."
  def alarm?, do: RateLimit.get(@site_key, @site_scale) >= @site_limit

  defp alarm do
    message = "Verify alarm: #{@site_limit} failed checks across the site in an hour"
    Logger.warning(message)
    Event.record!(:verify_alarm, data: %{misses: @site_limit})
    Honeybadger.notify(%RuntimeError{message: message}, fingerprint: "verify-alarm")
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
