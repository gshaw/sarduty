defmodule Web.ThemeController do
  use Web, :controller

  @doc "Saves a theme for this device (Web.Theme) and goes back to the page it came from."
  def update(conn, params) do
    theme = Web.Theme.parse(params["theme"])

    conn
    |> Web.Theme.put(theme)
    |> put_flash(:info, Web.Theme.saved(theme))
    |> redirect(to: local_path(params["return_to"]))
  end

  # Only a path on this site, so the form can't send anyone elsewhere.
  defp local_path("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: "/", else: path
  end

  defp local_path(_), do: "/"
end
