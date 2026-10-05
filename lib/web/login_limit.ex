defmodule Web.LoginLimit do
  @moduledoc """
  Caps login code requests, per email and per client IP, so the form can't be used to
  flood someone's inbox or to probe for emails. Over the cap, the page says the same as
  always; it just sends nothing.

  Also caps wrong codes. Each code dies after 5 misses, but asking again gets a fresh
  one, so misses also count per email over a day and per IP: 20 a day on one email makes
  guessing a six-digit code across new ones hopeless. Counters are in memory, so a
  deploy resets them.
  """

  alias App.RateLimit

  require Logger

  @scale :timer.minutes(15)
  @email_limit 5
  @ip_limit 20
  @miss_scale :timer.hours(24)
  @email_miss_limit 20
  @ip_miss_limit 50

  @doc "Counts a request, and says whether it's within both caps."
  def allow?(email, ip) do
    email_count = RateLimit.inc("login:email:#{String.downcase(email)}", @scale)
    ip_count = RateLimit.inc("login:ip:#{ip}", @scale)
    allowed = email_count <= @email_limit and ip_count <= @ip_limit

    unless allowed, do: Logger.warning("Login code limit reached from #{ip}")
    allowed
  end

  @doc "Whether this email or IP has used up its wrong codes for now."
  def guessing_blocked?(email, ip) do
    misses(:email, email) >= @email_miss_limit or misses(:ip, ip) >= @ip_miss_limit
  end

  @doc "Counts a wrong code, and logs when the email or IP reaches its cap."
  def miss(email, ip) do
    if count_miss(:email, email) == @email_miss_limit,
      do: Logger.warning("Login code miss limit reached for an email, from #{ip}")

    if count_miss(:ip, ip) == @ip_miss_limit,
      do: Logger.warning("Login code miss limit reached from #{ip}")

    :ok
  end

  defp misses(kind, value), do: kind |> miss_key(value) |> RateLimit.get(@miss_scale)
  defp count_miss(kind, value), do: kind |> miss_key(value) |> RateLimit.inc(@miss_scale)

  defp miss_key(:email, email),
    do: "login:miss:email:#{email |> String.trim() |> String.downcase()}"

  defp miss_key(:ip, ip), do: "login:miss:ip:#{ip}"
end
