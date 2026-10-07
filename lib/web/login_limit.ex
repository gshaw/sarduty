defmodule Web.LoginLimit do
  @moduledoc """
  Caps login code requests, per email or phone number and per client IP, so the form
  can't be used to flood someone's inbox or phone, or to probe for who has access. Over
  the cap, the page says the same as always; it just sends nothing. A number gets fewer
  codes than an email, because each text costs money.

  Also caps wrong codes. Each code dies after 5 misses, but asking again gets a fresh
  one, so misses also count per email or number over a day and per IP: 20 a day on one
  makes guessing a six-digit code across new ones hopeless. Counters are in memory, so a
  deploy resets them.

  A browser that has logged in to the account before (Web.UserAuth.known_browser?/2)
  skips the per-account count, so nobody can lock a person out of their own browsers by
  entering wrong codes for them (#176). Only the per-IP cap applies to it.

  A number is passed as `{:phone, e164}`, an email as a string.
  """

  alias App.RateLimit

  require Logger

  @scale :timer.minutes(15)
  @email_limit 5
  @phone_limit 3
  @ip_limit 20
  @miss_scale :timer.hours(24)
  @email_miss_limit 20
  @ip_miss_limit 50

  @doc """
  Counts a request. `:ok` within both caps, `:limit_reached` for the one that first goes
  over either, and `:limited` after that, so a flood records one event, not thousands.
  """
  def check(who, ip) do
    {key, limit} = request_key(who)
    who_count = RateLimit.inc(key, @scale)
    ip_count = "login:ip" |> ip_key(ip) |> RateLimit.inc(@scale)

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

  @doc """
  Whether this email or number, or this IP, has used up its wrong codes for now. A known
  browser is held only to the IP's cap.
  """
  def guessing_blocked?(who, ip, known_browser? \\ false) do
    (not known_browser? and misses(miss_key(who)) >= @email_miss_limit) or
      misses(ip_key("login:miss:ip", ip)) >= @ip_miss_limit
  end

  @doc """
  Counts a wrong code, and logs when the email or number, or the IP, reaches its cap.
  Returns what this miss blocked: `:account`, `:ip`, both, or neither. A known browser's
  misses don't count against the account.
  """
  def miss(who, ip, known_browser? \\ false) do
    account? = not known_browser? and count_miss(miss_key(who)) == @email_miss_limit
    if account?, do: Logger.warning("Login code miss limit reached for an account, from #{ip}")

    ip? = count_miss(ip_key("login:miss:ip", ip)) == @ip_miss_limit
    if ip?, do: Logger.warning("Login code miss limit reached from #{ip}")

    for {scope, true} <- [account: account?, ip: ip?], do: scope
  end

  defp request_key({:phone, phone}), do: {"login:phone:#{phone}", @phone_limit}
  defp request_key(email), do: {"login:email:#{normalize(email)}", @email_limit}

  defp misses(key), do: RateLimit.get(key, @miss_scale)
  defp count_miss(key), do: RateLimit.inc(key, @miss_scale)

  defp miss_key({:phone, phone}), do: "login:miss:phone:#{phone}"
  defp miss_key(email), do: "login:miss:email:#{normalize(email)}"

  defp ip_key(prefix, ip), do: "#{prefix}:#{RateLimit.ip_key(ip)}"

  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
