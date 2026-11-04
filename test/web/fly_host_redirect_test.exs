defmodule Web.FlyHostRedirectTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Web.FlyHostRedirect

  @hosts ["sarduty.fly.dev"]

  test "Fly's host goes to the app's URL, path and query kept" do
    conn = conn(:get, "https://sarduty.fly.dev/teams/nsr?x=1") |> FlyHostRedirect.redirect(@hosts)

    assert conn.halted
    assert conn.status == 301
    assert Plug.Conn.get_resp_header(conn, "location") == [Web.Endpoint.url() <> "/teams/nsr?x=1"]
  end

  test "every other host is left alone, dev ones included" do
    for host <- ~w(sarduty.test sarduty-orgs.test sarduty.gshaw.ca localhost other.fly.dev) do
      conn = conn(:get, "https://#{host}/") |> FlyHostRedirect.redirect(@hosts)
      refute conn.halted, host
    end
  end

  test "nothing redirects unless configured" do
    refute Application.get_env(:sarduty, :redirect_hosts)
  end
end
