defmodule Web.FlyHostRedirect do
  @moduledoc """
  Sends Fly's own host, `sarduty.fly.dev`, to the app's URL (#824). That host serves the
  whole app, but LiveView can't connect from it. Only the exact hosts in
  `config :sarduty, :redirect_hosts`, which prod alone sets: dev runs under sarduty.test,
  sarduty-orgs.test, sarduty.gshaw.ca, and localhost, and must never be sent away.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: redirect(conn, Application.get_env(:sarduty, :redirect_hosts, []))

  @doc "Redirects when the request's host is one of `hosts`."
  def redirect(%Plug.Conn{host: host} = conn, hosts) do
    if host in hosts do
      query = if conn.query_string == "", do: "", else: "?" <> conn.query_string

      conn
      |> put_resp_header("location", Web.Endpoint.url() <> conn.request_path <> query)
      |> send_resp(301, "")
      |> halt()
    else
      conn
    end
  end
end
