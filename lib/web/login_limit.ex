defmodule Web.LoginLimit do
  @moduledoc """
  Caps login code requests, per email or phone number and per client IP, so the form
  can't be used to flood someone's inbox or phone, or to probe for who has access. Over
  the cap, the page says the same as always; it just sends nothing. A number gets fewer
  codes than an email, because each text costs money, and at most 30 a day.

  Also caps wrong codes. Each code dies after 5 misses, but asking again gets a fresh
  one, so misses also count per email or number and per IP over the last 24 hours: 20 on
  one account makes guessing an 8-digit code across new ones hopeless, and 50 on one IP
  (IPv6 by its /64). Both those caps and the daily text cap count rows in the events
  table (App.Model.Event, by `who` and `ip_key`, #975), so a deploy doesn't reset them.
  The 15-minute request caps are flood control and stay in memory.

  A browser that has logged in to the account before (Web.UserAuth.known_browser?/2)
  skips the per-account count, so nobody can lock a person out of their own browsers by
  entering wrong codes for them (#176). Only the per-IP cap applies to it.

  A number is passed as `{:phone, e164}`, an email as a string. `source` is what
  Web.SecurityEvent.record/3 takes: a conn, or a LiveView's assigns.
  """

  alias App.Model.Event
  alias App.RateLimit
  alias App.Repo
  alias Web.SecurityEvent

  require Logger

  @scale :timer.minutes(15)
  @email_limit 5
  @phone_limit 3
  @ip_limit 20
  @texts_a_day 30
  @account_miss_limit 20
  @ip_miss_limit 50

  @doc """
  Counts a request for a code, and whether to send it. Records each request within the
  caps as `login_code_requested`, which the daily text cap counts, and the first one over
  them as `login_code_limited`, so a flood records one event, not thousands. `via` is
  "email", "text", or "confirm" for a member's new number.
  """
  def request(source, who, ip, via) do
    hash = Event.who(who)
    attrs = [email_or_phone: who, data: %{via: via}]

    # One writer at a time, so two requests at once can't both be the 30th text.
    {:ok, result} =
      Repo.transaction(fn ->
        result = check(who, hash, ip)

        case result do
          :ok -> SecurityEvent.record(source, :login_code_requested, attrs)
          :limit_reached -> SecurityEvent.record(source, :login_code_limited, attrs)
          :limited -> :ok
        end

        result
      end)

    result == :ok
  end

  # `:ok` within every cap, `:limit_reached` for the request that first goes over one,
  # and `:limited` after that.
  defp check(who, hash, ip) do
    case check_flood(who, ip) do
      :ok -> check_texts(who, hash, ip)
      over -> over
    end
  end

  defp check_flood(who, ip) do
    {key, limit} = request_key(who)
    who_count = RateLimit.inc(key, @scale)
    ip_count = RateLimit.inc("login:ip:#{RateLimit.ip_key(ip)}", @scale)

    cond do
      who_count <= limit and ip_count <= @ip_limit ->
        :ok

      who_count == limit + 1 or ip_count == @ip_limit + 1 ->
        Logger.warning("Login code limit reached from #{ip}")
        :limit_reached

      true ->
        :limited
    end
  end

  # Requests over the daily cap aren't recorded, so the count stays at 30. The first one
  # over records `login_code_limited` unless the number already has one that day.
  defp check_texts({:phone, _phone}, hash, ip) do
    since = day_ago()

    cond do
      Event.count_since(:login_code_requested, since, who: hash) < @texts_a_day ->
        :ok

      Event.count_since(:login_code_limited, since, who: hash) == 0 ->
        Logger.warning("Daily text limit reached for a number, from #{ip}")
        :limit_reached

      true ->
        :limited
    end
  end

  defp check_texts(_email, _hash, _ip), do: :ok

  @doc """
  Whether this email or number, or this IP, has used up its wrong codes for now. A known
  browser is held only to the IP's cap.
  """
  def guessing_blocked?(who, ip, known_browser? \\ false) do
    since = day_ago()

    (not known_browser? and account_misses(Event.who(who), since) >= @account_miss_limit) or
      ip_misses(ip, since) >= @ip_miss_limit
  end

  @doc """
  Records a wrong code as `login_code_missed`, with `data` (`via` and `known_browser`),
  and returns what it blocked: `:account`, `:ip`, both, or neither. Each block is
  recorded as `login_blocked`. A known browser's misses don't count against the account.

  The miss and the count are one transaction, and SQLite has one writer, so two misses at
  once count 20 and 21, and only one of them blocks. The count looks back 24 hours, so it
  drops below the cap as old misses age out, and one more wrong code takes it back to the
  cap. That isn't a new block while one stands from the last 24 hours, so the owner gets
  one email a day, not one per aged-out miss.
  """
  def miss(source, who, ip, data) do
    hash = Event.who(who)

    {:ok, blocks} =
      Repo.transaction(fn ->
        SecurityEvent.record(source, :login_code_missed, email_or_phone: who, data: data)
        since = day_ago()

        account? =
          not data.known_browser and account_misses(hash, since) == @account_miss_limit and
            not blocked_since?(since, who: hash, data: %{scope: "account"})

        ip? =
          ip_misses(ip, since) == @ip_miss_limit and
            not blocked_since?(since, ip_key: RateLimit.ip_key(ip), data: %{scope: "ip"})

        for {scope, true} <- [account: account?, ip: ip?] do
          Logger.warning("Login code miss limit reached (#{scope}) from #{ip}")

          SecurityEvent.record(source, :login_blocked,
            email_or_phone: who,
            data: Map.put(data, :scope, scope)
          )

          scope
        end
      end)

    blocks
  end

  defp account_misses(hash, since),
    do: Event.count_since(:login_code_missed, since, who: hash, data: %{known_browser: false})

  defp ip_misses(ip, since),
    do: Event.count_since(:login_code_missed, since, ip_key: RateLimit.ip_key(ip))

  defp blocked_since?(since, opts), do: Event.count_since(:login_blocked, since, opts) > 0

  defp day_ago, do: DateTime.add(DateTime.utc_now(), -1, :day)

  defp request_key({:phone, phone}), do: {"login:phone:#{phone}", @phone_limit}
  defp request_key(email), do: {"login:email:#{normalize(email)}", @email_limit}

  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
