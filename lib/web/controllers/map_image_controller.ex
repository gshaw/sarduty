defmodule Web.MapImageController do
  use Web, :controller

  alias App.Adapter.Mapbox
  alias Web.MapImage

  @doc """
  Fetches a signed map from Mapbox and sends it on, with Mapbox's own cache header. An
  unsigned or altered key is not found.
  """
  def show(conn, %{"key" => key}) do
    with {:ok, path} <- MapImage.verify(key),
         {:ok, image} <- Mapbox.fetch_static_image(Mapbox.build_context(), path) do
      conn
      |> put_resp_content_type(image.content_type, nil)
      |> put_resp_header("cache-control", image.cache_control || "public, max-age=43200")
      |> send_resp(200, image.body)
    else
      :error -> raise Web.Status.NotFound
      {:error, _reason} -> send_resp(conn, 502, "")
    end
  end
end
