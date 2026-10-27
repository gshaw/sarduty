defmodule Web.HealthTest do
  # Not Web.ConnCase: that checks out a database connection for every test, and the 503
  # test needs a process the database won't answer.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox

  @endpoint Web.Endpoint

  test "200 ok when the database answers, on any host" do
    Sandbox.checkout(App.Repo)

    conn = get(%{build_conn() | host: "anything.example"}, "/health")

    assert response(conn, 200) == "ok"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "503 when the database doesn't answer" do
    conn = get(build_conn(), "/health")

    assert response(conn, 503) == "database down"
  end
end
