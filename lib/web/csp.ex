defmodule Web.CSP do
  @moduledoc """
  The one Content-Security-Policy, for every page on both hosts. It stops script that
  gets into a page, through a bug that skips HTML escaping, from running: scripts load
  only from SAR Duty's own files, never inline.

  So no inline JS anywhere: no `<script>` without `src`, no `on…=` handler attribute in a
  template. Put it in assets/js. Web.CSPTest refuses both. Adding something from another
  site (map tiles, an embed) means adding its origin here, on purpose.

  Sent as `Content-Security-Policy-Report-Only` first: browsers report what the policy
  would block to /csp-reports (Web.CSPReportController), which logs it, and block
  nothing. Once the logs are quiet, `header/0` changes to `content-security-policy`.

  - `'wasm-unsafe-eval'`: the barcode reader is WebAssembly (assets/js/barcode_reader.js).
  - `'report-sample'`: a report of blocked inline script carries its first 40
    characters, which tells SAR Duty's own from a browser extension's.
  - img-src the app's host: verify pages show team and organization logos from it.
  - `style-src 'unsafe-inline'`: `style=` attributes, and the styles Trix and LiveView
    set. An injected style can't run code.
  - No `form-action`: the agent authorize form redirects to the agent's own callback
    (#761), which is on another site, so `'self'` would break it.
  """

  def policy do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'wasm-unsafe-eval' 'report-sample'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' #{Web.Endpoint.url()} data: blob:",
        "font-src 'self'",
        "connect-src 'self'",
        "media-src 'self' blob:",
        "worker-src 'self' blob:",
        "object-src 'none'",
        "base-uri 'self'",
        "frame-ancestors 'self'"
      ],
      "; "
    )
  end

  @doc "The header the policy goes in."
  def header, do: "content-security-policy-report-only"

  @doc """
  The header for `put_secure_browser_headers/2`. Reports go to the app's own host, also
  from the verify site, whose other paths redirect to the app.
  """
  def headers,
    do: %{header() => policy() <> "; report-uri " <> Web.Endpoint.url() <> "/csp-reports"}
end
