defmodule Web.VerifyController do
  use Web, :controller

  @doc "Anything else on the verify site is the app's, so it goes there."
  def to_app(conn, _params) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    redirect(conn, external: Web.Endpoint.url() <> conn.request_path <> query)
  end
end
