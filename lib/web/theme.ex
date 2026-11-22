defmodule Web.Theme do
  @moduledoc """
  The theme a device chose: System, Light, or Dark. theme.js saves it in the `theme`
  cookie, and this plug reads it so the root layout renders `data-theme` itself and
  nothing flashes. Its own cookie, not the session: the session cookie ends when the
  browser quits and is cleared at every log in and log out. No cookie, or one that isn't
  light or dark, is System.
  """

  @behaviour Plug

  import Plug.Conn

  @themes ~w(light dark)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    assign(conn, :theme, parse(conn.cookies["theme"]))
  end

  @doc "The saved theme, or nil for System."
  def parse(theme) when theme in @themes, do: theme
  def parse(_), do: nil

  @doc "The top bar's navy in each theme, which the browser's own colour matches."
  def nav_color("light"), do: "#13243a"
  def nav_color("dark"), do: "#0a111b"
end
