defmodule Web.VerifyController do
  use Web, :controller

  @doc """
  The app's /verify links, from before the verify site: cards linked
  `sarduty.com/VERIFY/<code>`, and bookmarks of /verify. Sent on to the same check there.
  """
  def to_verify(conn, %{"code" => code} = params) do
    path =
      if Map.has_key?(conn.path_params, "code"),
        do: "/" <> URI.encode_www_form(code),
        else: "/?" <> URI.encode_query(code: params["code"])

    redirect(conn, external: Web.VerifyHost.url() <> path)
  end

  def to_verify(conn, _params), do: redirect(conn, external: Web.VerifyHost.url() <> "/")

  @doc "Anything else on the verify site is the app's, so it goes there."
  def to_app(conn, _params) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    redirect(conn, external: Web.Endpoint.url() <> conn.request_path <> query)
  end
end
