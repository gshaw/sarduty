defmodule Web.CSPReport do
  @moduledoc """
  One report of what the Content-Security-Policy (Web.CSP) would block, read from what a
  browser sent, for the log line and for Honeybadger.

  Browser extensions' reports are noise: they're logged, never sent to Honeybadger. An
  extension shows in what was blocked (`chrome-extension:` and the like) or, for inline
  script an extension adds to the page, in the report's source file. Every other kind
  goes to Honeybadger grouped by `fingerprint/1`: the directive, what was blocked (its
  host, or `inline`, `eval`, `data`), and the page with ids, team names, tokens and card
  codes replaced. So a thousand reports of one problem are one fault with a count.
  """

  @noise ~w(chrome-extension moz-extension safari-extension safari-web-extension about)

  defstruct directive: "?", blocked: "?", page: "?", source: nil, sample: nil

  @doc "The report's fields, from the old `csp-report` shape or the Reporting API's."
  def new(report) when is_map(report) do
    %__MODULE__{
      directive:
        field(report, ["effective-directive", "effectiveDirective", "violated-directive"]),
      blocked: field(report, ["blocked-uri", "blockedURL"]),
      page: report |> field(["document-uri", "documentURL"]) |> page_path(),
      source: report |> field(["source-file", "sourceFile"], nil) |> source(),
      sample: field(report, ["script-sample", "sample"], nil)
    }
  end

  def message(%__MODULE__{} = r), do: "CSP would block #{r.blocked} (#{r.directive}) on #{r.page}"

  @doc "The message with where it came from and the script's start, for the log."
  def log_line(%__MODULE__{} = r) do
    [message(r), r.source && "from #{r.source}", r.sample && "sample #{inspect(r.sample)}"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  @doc "A browser extension's doing, not SAR Duty's."
  def noise?(%__MODULE__{blocked: blocked, source: source}),
    do: extension?(blocked) or extension?(source)

  defp extension?(nil), do: false
  defp extension?(url), do: Enum.any?(@noise, &String.starts_with?(url, &1 <> ":"))

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

  defp field(report, keys, default \\ "?"),
    do: Enum.find_value(keys, default, &to_text(report[&1]))

  # A page of ours is only its path, like `page`; an extension's script stays whole.
  defp source(nil), do: nil

  defp source(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> page_path(url)
      _ -> url
    end
  end

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
