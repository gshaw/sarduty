defmodule App.RateLimitTest do
  use ExUnit.Case, async: true

  alias App.RateLimit

  test "an IPv4 address counts on its own" do
    assert RateLimit.ip_key("203.0.113.7") == "203.0.113.7"
    refute RateLimit.ip_key("203.0.113.7") == RateLimit.ip_key("203.0.113.8")
  end

  test "IPv6 addresses in one /64 share a key" do
    a = RateLimit.ip_key("2001:db8:1:2:aaaa::1")
    b = RateLimit.ip_key("2001:db8:1:2:ffff:ffff:ffff:ffff")

    assert a == "2001:db8:1:2::/64"
    assert a == b
    refute a == RateLimit.ip_key("2001:db8:1:3::1")
  end

  test "anything else is used as is" do
    assert RateLimit.ip_key("test-1") == "test-1"
  end
end
