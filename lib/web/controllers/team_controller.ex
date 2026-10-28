defmodule Web.TeamController do
  use Web, :controller

  alias App.Model.Team
  alias App.Operation.LoadImage

  # The team logo padded square, for the round spot on Google passes. ?shape=square
  # leaves off the margin the circle needs, for the dashboards and verify page. ?shape=fit
  # is the logo at its own shape with no padding, for the Dashboard's head, which sizes
  # it by height so the gap beside it is the gap. Public, because Google loads it from
  # this URL. A team without a logo gets SAR Duty's.
  def logo(conn, %{"subdomain" => subdomain} = params) do
    shape =
      case params["shape"] do
        "square" -> :square
        "fit" -> :logo
        _other -> :round
      end

    case Team.get_by(subdomain: subdomain) do
      %Team{} = team ->
        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> put_resp_content_type("image/png", nil)
        |> send_resp(200, LoadImage.logo(team, shape))

      nil ->
        send_resp(conn, :not_found, "")
    end
  end
end
