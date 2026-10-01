defmodule Web.TeamController do
  use Web, :controller

  alias App.Model.Team
  alias App.Operation.LoadImage

  # The team logo padded square, for the dashboard and the round spot on Google passes.
  # Public, because Google loads it from this URL. A team without a logo gets SAR Duty's.
  def logo(conn, %{"subdomain" => subdomain}) do
    case Team.get_by(subdomain: subdomain) do
      %Team{} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> put_resp_content_type("image/png", nil)
        |> send_resp(200, LoadImage.logo(subdomain, :round))

      nil ->
        send_resp(conn, :not_found, "")
    end
  end
end
