defmodule Web.CSPReportController do
  @moduledoc """
  Logs what the Content-Security-Policy would block (Web.CSP), one warning line per
  report, for bin/fly-logs. Browsers send the old `application/csp-report` shape
  (`{"csp-report": {...}}`) or the Reporting API's list of `{"body": {...}}`. Anything
  else is ignored. Always 204: a browser does nothing with the answer.
  """
  use Web, :controller

  require Logger

  @max_body 16_000

  # Plug.Parsers already decoded `application/reports+json` (a `+json` type) into `_json`.
  def create(conn, %{"_json" => reports}) when is_list(reports) do
    reports |> from_list() |> Enum.each(&log/1)
    send_resp(conn, :no_content, "")
  end

  def create(conn, _params) do
    case Plug.Conn.read_body(conn, length: @max_body) do
      {:ok, body, conn} ->
        body |> decode() |> Enum.each(&log/1)
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

  defp log(report) do
    Logger.warning(fn ->
      directive =
        field(report, ["effective-directive", "effectiveDirective", "violated-directive"])

      blocked = field(report, ["blocked-uri", "blockedURL"])
      page = report |> field(["document-uri", "documentURL"]) |> page_path()
      "CSP would block #{blocked} (#{directive}) on #{page}"
    end)
  end

  defp field(report, keys), do: Enum.find_value(keys, "?", &(report[&1] |> to_text()))

  defp to_text(value) when is_binary(value) and value != "", do: String.slice(value, 0, 200)
  defp to_text(_value), do: nil

  # Only the path, with card codes cut as in the request log, and no query: a page's
  # address can carry a token (/replies/:token is one).
  defp page_path(url) do
    case URI.parse(url) do
      %URI{host: page_host, path: path} when is_binary(path) ->
        page_host |> Web.RequestLog.filter_path(path) |> cut_tokens()

      _ ->
        "?"
    end
  end

  defp cut_tokens(path),
    do: Regex.replace(~r{^/(replies|reminders)/[^/]+}, path, "/\\1/[FILTERED]")
end
