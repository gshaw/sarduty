defmodule Web.OrganizationController do
  use Web, :controller

  alias App.Model.Organization
  alias App.Operation.LoadImage

  @doc "The logo's full URL, since the verify site is another host. Changes with the logo."
  def logo_url(%Organization{} = organization) do
    version = DateTime.to_unix(organization.updated_at)
    "#{Web.Endpoint.url()}/organizations/#{organization.slug}/logo?v=#{version}"
  end

  # The organization's logo padded square, for the verify site's bar and results. Public,
  # like team logos. The query string changes when the logo does, so it caches long.
  def logo(conn, %{"slug" => slug}) do
    case Organization.get_by_slug(slug) do
      %Organization{logo: logo} = organization when is_binary(logo) ->
        conn
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> put_resp_content_type("image/png", nil)
        |> send_resp(200, LoadImage.organization_logo(organization, :square))

      _ ->
        send_resp(conn, :not_found, "")
    end
  end
end
