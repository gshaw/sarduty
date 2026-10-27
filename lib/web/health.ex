defmodule Web.Health do
  @moduledoc """
  `GET /health` for Fly's check (#106): 200 `ok` when the database answers `SELECT 1`,
  503 when it doesn't. It runs ahead of everything else in Web.Endpoint, so it needs no
  session or host, and skips the request log and Honeybadger Insights, which the check
  would fill every 15 seconds.
  """

  @behaviour Plug

  import Plug.Conn

  alias Ecto.Adapters.SQL

  require Logger

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: ["health"], method: method} = conn, _opts)
      when method in ["GET", "HEAD"] do
    {status, body} = if database_answers?(), do: {200, "ok"}, else: {503, "database down"}

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, body)
    |> halt()
  end

  def call(conn, _opts), do: conn

  # A Repo that isn't running, or a pool with no connection to give, raises.
  defp database_answers? do
    match?({:ok, _}, SQL.query(App.Repo, "SELECT 1", []))
  rescue
    error ->
      Logger.warning("Health check: #{Exception.message(error)}")
      false
  end
end
