defmodule Web.RequestLogTest do
  use Web.ConnCase

  import ExUnit.CaptureLog

  alias Web.RequestLog

  describe "filter_path/2" do
    test "cuts attendance tokens, short link codes and card codes" do
      assert RequestLog.filter_path("sarduty.com", "/attendance/abc") == "/attendance/[FILTERED]"
      assert RequestLog.filter_path("sarduty.com", "/s/ABC123") == "/s/[FILTERED]"

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

    test "logs a short link request without its code, and the code param filtered", %{conn: conn} do
      log =
        capture_log([level: :info], fn ->
          assert_error_sent 404, fn -> get(conn, "/s/SECRETCODE") end
        end)

      assert log =~ "GET /s/[FILTERED]"
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
