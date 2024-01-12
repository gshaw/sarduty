defmodule Web.TeamController do
  use Web, :controller

  alias App.Model.Team

  def image(conn, params) do
    path = Team.logo_path(params["subdomain"])

    send_download(
      conn,
      {:file, path},
      disposition: :inline
    )
  end
end
