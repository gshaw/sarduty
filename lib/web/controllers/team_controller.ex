defmodule Web.TeamController do
  use Web, :controller

  alias App.Model.Team

  def image(conn, params) do
    case Team.logo_file(params["subdomain"]) do
      nil -> send_resp(conn, :not_found, "")
      path -> send_download(conn, {:file, path}, disposition: :inline)
    end
  end
end
