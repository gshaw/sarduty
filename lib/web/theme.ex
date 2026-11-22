defmodule Web.Theme do
  @moduledoc """
  The theme a device chose: System, Light, or Dark. Web.ThemeController saves it in the
  `theme` cookie, and this plug reads it so the root layout renders `data-theme` itself and
  nothing flashes. Its own cookie, not the session: the session cookie ends when the
  browser quits and is cleared at every log in and log out. No cookie, or one that isn't
  light or dark, is System.

  The plug copies it into the session too, where a LiveView can read it (`"theme"`), and
  saves the cookie again, since Chrome keeps one 400 days at most.
  """

  @behaviour Plug

  import Plug.Conn

  @themes ~w(light dark)
  @max_age 400 * 24 * 60 * 60

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    theme = parse(conn.cookies["theme"])

    conn
    |> refresh(theme)
    |> sync_session(theme)
    |> assign(:theme, theme)
  end

  @doc "The saved theme, or nil for System."
  def parse(theme) when theme in @themes, do: theme
  def parse(_), do: nil

  @doc "Saves `theme` for this device; nil goes back to System."
  def put(conn, nil), do: delete_resp_cookie(conn, "theme")

  def put(conn, theme) when theme in @themes,
    do: put_resp_cookie(conn, "theme", theme, max_age: @max_age, same_site: "Lax")

  @doc "The toast once a theme is saved."
  def saved(nil), do: "The theme follows this device's setting."
  def saved("light"), do: "Light on this device."
  def saved("dark"), do: "Dark on this device."

  @doc "The top bar's navy in each theme, which the browser's own colour matches."
  def nav_color("light"), do: "#13243a"
  def nav_color("dark"), do: "#0a111b"

  defp refresh(conn, nil), do: conn
  defp refresh(conn, theme), do: put(conn, theme)

  defp sync_session(conn, theme) do
    if get_session(conn, "theme") == theme, do: conn, else: put_session(conn, "theme", theme)
  end
end
