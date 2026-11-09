defmodule Web.CSPTest do
  # The one Content-Security-Policy (Web.CSP): on both hosts' pages, no inline JS in any
  # template, and the reports it sends are logged without tokens.
  use Web.ConnCase

  import ExUnit.CaptureLog

  defp csp(conn), do: conn |> get_resp_header(Web.CSP.header()) |> List.first()

  test "an app page sends the policy, reporting to the app's host", %{conn: conn} do
    conn = get(conn, "/styles")
    assert html_response(conn, 200)
    assert csp(conn) =~ Web.CSP.policy()
    assert csp(conn) =~ "report-uri #{Web.Endpoint.url()}/csp-reports"
  end

  test "a verify page sends the same policy", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, Web.VerifyHost.host())
      |> put_req_header("fly-client-ip", "10.5.#{System.unique_integer([:positive])}")
      |> get("/")

    assert html_response(conn, 200)
    assert csp(conn) =~ Web.CSP.policy()
  end

  test "scripts load only from SAR Duty's own files" do
    [scripts] = Regex.run(~r/script-src ([^;]+)/, Web.CSP.policy(), capture: :all_but_first)
    refute scripts =~ "unsafe-inline"
    refute scripts =~ "'unsafe-eval'"
    refute scripts =~ "*"
  end

  test "verify pages may show logos from the app's host" do
    [images] = Regex.run(~r/img-src ([^;]+)/, Web.CSP.policy(), capture: :all_but_first)
    assert images =~ Web.Endpoint.url()
  end

  # The policy refuses inline JS, so a template with any would break in the browser.
  test "no template has an inline script or an on…= handler" do
    files = Path.wildcard("lib/**/*.{ex,heex}") -- ["lib/web/csp.ex"]
    inline_script = ~r/<script(?![^>]*\bsrc=)[^>]*>/
    handler = ~r/\son[a-z]+=["{]/

    offenders =
      for file <- files,
          {line, n} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          line =~ inline_script or line =~ handler,
          do: "#{file}:#{n}: #{String.trim(line)}"

    assert offenders == [], "Move it to assets/js (Web.CSP):\n" <> Enum.join(offenders, "\n")
  end

  describe "POST /csp-reports" do
    test "logs an old-style report, page path only, with the token cut", %{conn: conn} do
      report = %{
        "csp-report" => %{
          "document-uri" => "https://sarduty.com/replies/SECRETTOKEN?a=1",
          "effective-directive" => "script-src-elem",
          "blocked-uri" => "https://evil.example/x.js"
        }
      }

      log =
        capture_log(fn ->
          conn =
            conn
            |> put_req_header("content-type", "application/csp-report")
            |> post("/csp-reports", Jason.encode!(report))

          assert response(conn, 204)
        end)

      assert log =~
               "CSP would block https://evil.example/x.js (script-src-elem) on /replies/[FILTERED]"

      refute log =~ "SECRETTOKEN"
      refute log =~ "a=1"
    end

    test "logs Reporting API reports", %{conn: conn} do
      reports = [
        %{
          "type" => "csp-violation",
          "body" => %{
            "documentURL" => "https://sarduty.com/styles",
            "effectiveDirective" => "img-src",
            "blockedURL" => "https://tiles.example/1.png"
          }
        }
      ]

      log =
        capture_log(fn ->
          conn =
            conn
            |> put_req_header("content-type", "application/reports+json")
            |> post("/csp-reports", Jason.encode!(reports))

          assert response(conn, 204)
        end)

      assert log =~ "CSP would block https://tiles.example/1.png (img-src) on /styles"
    end

    test "ignores anything else", %{conn: conn} do
      log =
        capture_log(fn ->
          conn =
            conn
            |> put_req_header("content-type", "text/plain")
            |> post("/csp-reports", "hello")

          assert response(conn, 204)
        end)

      refute log =~ "CSP would block"
    end
  end

  describe "Web.CSPReport" do
    alias Web.CSPReport

    defp report(blocked, page, directive \\ "img-src"),
      do:
        CSPReport.new(%{
          "blocked-uri" => blocked,
          "document-uri" => page,
          "effective-directive" => directive
        })

    defp noise?(blocked), do: blocked |> report("https://sarduty.com/") |> CSPReport.noise?()

    defp fingerprint(blocked, page, directive \\ "img-src"),
      do: blocked |> report(page, directive) |> CSPReport.fingerprint()

    test "browser extensions are noise, SAR Duty's own problems aren't" do
      assert noise?("chrome-extension://abc/x.js")
      assert noise?("moz-extension://abc/x.js")
      refute noise?("inline")
      refute noise?("https://tiles.example/1.png")
    end

    test "inline script an extension adds is noise, by its source file" do
      from = fn source ->
        CSPReport.new(%{
          "blocked-uri" => "inline",
          "document-uri" => "https://sarduty.com/replies/SECRET",
          "effective-directive" => "script-src-elem",
          "source-file" => source,
          "script-sample" => "window.__x = 1"
        })
      end

      assert "chrome-extension://abc/content.js" |> from.() |> CSPReport.noise?()
      assert "safari-web-extension://abc/inject.js" |> from.() |> CSPReport.noise?()

      ours = from.("https://sarduty.com/replies/SECRET?a=1")
      refute CSPReport.noise?(ours)
      assert ours.source == "/replies/[FILTERED]"

      assert CSPReport.log_line(ours) ==
               ~s{CSP would block inline (script-src-elem) on /replies/[FILTERED], } <>
                 ~s{from /replies/[FILTERED], sample "window.__x = 1"}
    end

    test "one fingerprint for one problem, whatever the team, id or token" do
      a =
        fingerprint(
          "https://tiles.example/1.png",
          "https://sarduty.com/teams/sfsar/activities/12"
        )

      b =
        fingerprint(
          "https://tiles.example/9.png?x=1",
          "https://sarduty.com/teams/devsar/activities/3"
        )

      assert a == b
      assert a == "csp img-src tiles.example /teams/:name/activities/:id"

      assert fingerprint("inline", "https://sarduty.com/replies/SECRET", "script-src-elem") ==
               "csp script-src-elem inline /replies/[FILTERED]"
    end

    test "a different directive or page is a different problem" do
      a = fingerprint("https://tiles.example/1.png", "https://sarduty.com/styles/map")
      refute a == fingerprint("https://tiles.example/1.png", "https://sarduty.com/styles/chart")

      refute a ==
               fingerprint(
                 "https://tiles.example/1.png",
                 "https://sarduty.com/styles/map",
                 "connect-src"
               )
    end
  end
end
