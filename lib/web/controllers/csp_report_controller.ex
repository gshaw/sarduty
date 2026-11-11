defmodule Web.CSPReportController do
  @moduledoc """
  What the Content-Security-Policy would block (Web.CSP): a warning line per report for
  bin/fly-logs, and Honeybadger for anything that isn't a browser extension's
  (Web.CSPReport), at most once an hour per kind. So Fly's 7 days of logs aren't the
  only record, and a flood can't use up the plan.

  Browsers send the old `application/csp-report` shape (`{"csp-report": {...}}`) or the
  Reporting API's list of `{"body": {...}}`. Anything else is ignored. Always 204: a
  browser does nothing with the answer.
  """
  use Web, :controller

  alias App.RateLimit
  alias Web.CSPReport

  require Logger

  @max_body 16_000
  @notify_every :timer.hours(1)

  # Plug.Parsers already decoded `application/reports+json` (a `+json` type) into `_json`.
  def create(conn, %{"_json" => reports}) when is_list(reports) do
    reports |> from_list() |> Enum.each(&handle(&1, user_agent(conn)))
    send_resp(conn, :no_content, "")
  end

  def create(conn, _params) do
    case Plug.Conn.read_body(conn, length: @max_body) do
      {:ok, body, conn} ->
        body |> decode() |> Enum.each(&handle(&1, user_agent(conn)))
        send_resp(conn, :no_content, "")

      _too_big_or_error ->
        send_resp(conn, :no_content, "")
    end
  end

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, %{"csp-report" => report}} when is_map(report) -> [report]
      {:ok, reports} when is_list(reports) -> from_list(reports)
      _ -> []
    end
  end

  defp from_list(reports), do: for(%{"body" => report} when is_map(report) <- reports, do: report)

  defp user_agent(conn), do: conn |> get_req_header("user-agent") |> List.first()

  defp handle(raw, user_agent) do
    report = CSPReport.new(raw, user_agent)
    report |> CSPReport.log_line() |> Logger.warning()
    unless CSPReport.noise?(report), do: notify(report)
  end

  defp notify(report) do
    fingerprint = CSPReport.fingerprint(report)

    if RateLimit.inc("csp:" <> fingerprint, @notify_every) == 1 do
      report
      |> CSPReport.message()
      |> Honeybadger.notify(fingerprint: fingerprint, metadata: Map.from_struct(report))
    end
  end
end
