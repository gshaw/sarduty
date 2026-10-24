defmodule Web.RequestLogTest do
  use Web.ConnCase

  import ExUnit.CaptureLog

  alias Web.RequestLog

  describe "filter_path/2" do
    test "cuts card codes" do
      assert RequestLog.filter_path("sarduty.com", "/verify/K7Q4M2XA/photo") ==
               "/verify/[FILTERED]/photo"

      assert RequestLog.filter_path("sarduty.com", "/VERIFY/K7Q4M2XA") == "/VERIFY/[FILTERED]"
    end

    test "on the verify site, cuts a bare card code but not its other pages" do
      host = "verify.sarduty.com"

      assert RequestLog.filter_path(host, "/K7Q4M2XA") == "/[FILTERED]"
      assert RequestLog.filter_path(host, "/K7Q4M2XA/photo") == "/[FILTERED]/photo"
      assert RequestLog.filter_path(host, "/") == "/"
      assert RequestLog.filter_path(host, "/orgs/nsr") == "/orgs/nsr"
      assert RequestLog.filter_path(host, "/assets/app.js") == "/assets/app.js"
    end

    test "leaves other paths alone" do
      assert RequestLog.filter_path("sarduty.com", "/nsr/members/1") == "/nsr/members/1"
      assert RequestLog.filter_path("sarduty.com", "/K7Q4M2XA") == "/K7Q4M2XA"
    end
  end

  # Request lines are :info, under the tests' :warning, so these tests change the global
  # level and can't run async.
  describe "request lines" do
    setup do
      level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: level) end)
    end

    test "logs a path with a card code without the code", %{conn: conn} do
      log =
        capture_log([level: :info], fn ->
          assert conn |> get("/verify/SECRETCODE/photo") |> response(404)
        end)

      assert log =~ "GET /verify/[FILTERED]/photo"
      refute log =~ "SECRETCODE"
    end

    test "logs a login without its code", %{conn: conn} do
      log =
        capture_log([level: :info], fn ->
          post(conn, "/login", %{"user" => %{"email" => "a@example.com", "code" => "424242"}})
        end)

      assert log =~ "POST /login"
      refute log =~ "424242"
    end
  end
end
