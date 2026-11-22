defmodule Web.ThemeController do
  use Web, :controller

  @doc """
  Saves a theme for this device (Web.Theme) and goes back to the page it came from. theme.js
  saves in the background, with an x-theme-save header, when the page looks the same
  either way, and gets the cookie alone.
  """
  def update(conn, params) do
    theme = Web.Theme.parse(params["theme"])
    conn = Web.Theme.put(conn, theme)

    if background?(conn) do
      send_resp(conn, 204, "")
    else
      conn
      |> put_flash(:info, Web.Theme.saved(theme))
      |> redirect(to: local_path(params["return_to"]))
    end
  end

  defp background?(conn), do: get_req_header(conn, "x-theme-save") == ["background"]

  # Only a path on this site, so the form can't send anyone elsewhere.
  defp local_path("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: "/", else: path
  end

  defp local_path(_), do: "/"
end
