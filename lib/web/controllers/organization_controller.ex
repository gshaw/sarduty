defmodule Web.OrganizationController do
  use Web, :controller

  alias App.Model.Organization
  alias App.Operation.LoadImage

  @doc "The logo's full URL, since the verify site is another host. Changes with the logo."
  def logo_url(%Organization{logo_at: %DateTime{} = logo_at} = organization) do
    Web.Endpoint.url() <> ~p"/orgs/#{organization}/logo?#{[v: DateTime.to_unix(logo_at)]}"
  end

  # The organization's logo padded square, for the verify site's bar and results. Public,
  # like team logos. The query string changes when the logo does, so it caches long.
  def logo(conn, %{"slug" => slug}) do
    with %Organization{} = organization <- Organization.get_by_slug(slug),
         png when is_binary(png) <- LoadImage.organization_logo(organization, :square) do
      conn
      |> put_resp_header("cache-control", "public, max-age=86400")
      |> put_resp_content_type("image/png", nil)
      |> send_resp(200, png)
    else
      nil -> send_resp(conn, :not_found, "")
    end
  end
end
