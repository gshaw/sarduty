defmodule Web.CSPReport do
  @moduledoc """
  One report of what the Content-Security-Policy (Web.CSP) would block, read from what a
  browser sent, for the log line and for Honeybadger.

  Browser extensions' reports (`chrome-extension:` and the like) are noise: they're
  logged, never sent to Honeybadger. Every other kind goes to Honeybadger grouped by
  `fingerprint/1`: the directive, what was blocked (its host, or `inline`, `eval`,
  `data`), and the page with ids, team names, tokens and card codes replaced. So a
  thousand reports of one problem are one fault with a count.
  """

  @noise ~w(chrome-extension moz-extension safari-extension safari-web-extension about)

  defstruct directive: "?", blocked: "?", page: "?"

  @doc "The report's fields, from the old `csp-report` shape or the Reporting API's."
  def new(report) when is_map(report) do
    %__MODULE__{
      directive:
        field(report, ["effective-directive", "effectiveDirective", "violated-directive"]),
      blocked: field(report, ["blocked-uri", "blockedURL"]),
      page: report |> field(["document-uri", "documentURL"]) |> page_path()
    }
  end

  def message(%__MODULE__{} = r), do: "CSP would block #{r.blocked} (#{r.directive}) on #{r.page}"

  @doc "A browser extension's doing, not SAR Duty's."
  def noise?(%__MODULE__{blocked: blocked}),
    do: Enum.any?(@noise, &String.starts_with?(blocked, &1 <> ":"))

  @doc "What groups reports of the same problem in Honeybadger."
  def fingerprint(%__MODULE__{} = r),
    do: Enum.join(["csp", r.directive, blocked_kind(r.blocked), page_template(r.page)], " ")

  defp blocked_kind(blocked) do
    case URI.parse(blocked) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      %URI{scheme: scheme} when is_binary(scheme) -> scheme
      _ -> blocked
    end
  end

  # /teams/devsar/members/635 → /teams/:name/members/:id
  defp page_template(page) do
    page
    |> String.split("/")
    |> Enum.map_join("/", &if(&1 =~ ~r/^\d+$/, do: ":id", else: &1))
    |> String.replace(~r{^/(teams|orgs)/[^/]+}, "/\\1/:name")
  end

  defp field(report, keys), do: Enum.find_value(keys, "?", &to_text(report[&1]))

  defp to_text(value) when is_binary(value) and value != "", do: String.slice(value, 0, 200)
  defp to_text(_value), do: nil

  # Only the path, with card codes cut as in the request log, and no query: a page's
  # address can carry a token (/replies/:token is one).
  defp page_path(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when is_binary(path) ->
        host |> Web.RequestLog.filter_path(path) |> cut_tokens()

      _ ->
        "?"
    end
  end

  defp cut_tokens(path),
    do: Regex.replace(~r{^/(replies|reminders)/[^/]+}, path, "/\\1/[FILTERED]")
end
