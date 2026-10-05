defmodule Web.ShortLinkControllerTest do
  use Web.ConnCase

  alias App.Model.ShortLink

  # Each test gets its own client IP, since the limit's counters outlive a test.
  setup %{conn: conn} do
    ip = "10.2.#{System.unique_integer([:positive])}"
    %{conn: put_req_header(conn, "fly-client-ip", ip)}
  end

  test "a code redirects to its target", %{conn: conn} do
    link = ShortLink.create!("/attendance/abc")
    assert redirected_to(get(conn, ~p"/s/#{link.code}")) == "/attendance/abc"
  end

  test "an expired code is not found", %{conn: conn} do
    link = ShortLink.create!("/attendance/abc", expires_at: ~U[2020-01-01 00:00:00Z])

    assert_error_sent 404, fn -> get(conn, ~p"/s/#{link.code}") end
  end

  test "a missing code is not found", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/s/zzzzzzzz") end
    assert_error_sent 404, fn -> get(conn, ~p"/s/not-a-code") end
  end

  @tag :capture_log
  test "too many misses from one IP are refused, even for a real code", %{conn: conn} do
    link = ShortLink.create!("/attendance/abc")

    for _ <- 1..20, do: assert_error_sent(404, fn -> get(conn, ~p"/s/zzzzzzzz") end)

    assert_error_sent 429, fn -> get(conn, ~p"/s/#{link.code}") end
  end
end
