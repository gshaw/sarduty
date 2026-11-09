defmodule Web.VerifyController do
  use Web, :controller

  # The app's security.txt, on this host too (#824).
  defdelegate security_txt(conn, params), to: Web.SiteController
  defdelegate to_security_txt(conn, params), to: Web.SiteController

  @doc "Anything else on the verify site is the app's, so it goes there."
  def to_app(conn, _params) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    redirect(conn, external: Web.Endpoint.url() <> conn.request_path <> query)
  end
end
