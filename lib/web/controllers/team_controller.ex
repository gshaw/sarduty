defmodule Web.TeamController do
  use Web, :controller

  alias App.Model.Team
  alias App.Operation.LoadPassImage

  def image(conn, params) do
    case Team.logo_file(params["subdomain"]) do
      nil -> send_resp(conn, :not_found, "")
      path -> send_download(conn, {:file, path}, disposition: :inline)
    end
  end

  # The round logo on the team's Google passes. Public, because Google loads it from
  # this URL. A team without a logo gets SAR Duty's.
  def pass_logo(conn, %{"subdomain" => subdomain}) do
    case Team.get_by(subdomain: subdomain) do
      %Team{} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> put_resp_content_type("image/png", nil)
        |> send_resp(200, LoadPassImage.logo(subdomain, :round))

      nil ->
        send_resp(conn, :not_found, "")
    end
  end
end
