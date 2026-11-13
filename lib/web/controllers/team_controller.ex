defmodule Web.TeamController do
  use Web, :controller

  alias App.Model.Team
  alias App.Operation.LoadImage

  @doc """
  The logo's full URL, since the verify site is another host. `?v=` changes with the logo
  (`logo_at`), so a new one shows at once. Shapes are as `logo/2` sends them.
  """
  def logo_url(%Team{} = team, shape \\ :round) do
    query =
      Enum.reject(
        [shape: shape_param(shape), v: team.logo_at && DateTime.to_unix(team.logo_at)],
        fn {_key, value} -> is_nil(value) end
      )

    path = if query == [], do: ~p"/teams/#{team}/logo", else: ~p"/teams/#{team}/logo?#{query}"
    Web.Endpoint.url() <> path
  end

  defp shape_param(:round), do: nil
  defp shape_param(:square), do: "square"
  defp shape_param(:fit), do: "fit"

  # The team logo padded square, for the round spot on Google passes. ?shape=square
  # leaves off the margin the circle needs, for the dashboards and verify page. ?shape=fit
  # is the logo at its own shape with no padding, for the Dashboard's head, which sizes
  # it by height so the gap beside it is the gap. Public, because Google loads it from
  # this URL. A team without a logo gets SAR Duty's. A URL with ?v= names one logo, so it
  # caches for a year; one without may be a team whose logo is about to change.
  def logo(conn, %{"subdomain" => subdomain} = params) do
    shape =
      case params["shape"] do
        "square" -> :square
        "fit" -> :logo
        _other -> :round
      end

    cache =
      if params["v"],
        do: "public, max-age=31536000, immutable",
        else: "public, max-age=300"

    case Team.get_by(subdomain: subdomain) do
      %Team{} = team ->
        conn
        |> put_resp_header("cache-control", cache)
        |> put_resp_content_type("image/png", nil)
        |> send_resp(200, LoadImage.logo(team, shape))

      nil ->
        send_resp(conn, :not_found, "")
    end
  end
end
