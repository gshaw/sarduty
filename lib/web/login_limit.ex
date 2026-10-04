defmodule Web.LoginLimit do
  @moduledoc """
  Caps login link requests, per email and per client IP, so the form can't be used to
  flood someone's inbox or to probe for emails. Over the cap, the page says the same as
  always; it just sends nothing.
  """

  alias App.RateLimit

  require Logger

  @scale :timer.minutes(15)
  @email_limit 5
  @ip_limit 20

  @doc "Counts a request, and says whether it's within both caps."
  def allow?(email, ip) do
    email_count = RateLimit.inc("login:email:#{String.downcase(email)}", @scale)
    ip_count = RateLimit.inc("login:ip:#{ip}", @scale)
    allowed = email_count <= @email_limit and ip_count <= @ip_limit

    unless allowed, do: Logger.warning("Login link limit reached from #{ip}")
    allowed
  end
end
