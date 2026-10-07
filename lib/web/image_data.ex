defmodule Web.ImageData do
  @doc "A PNG as a `data:` URL, for an image that is stored in a row and has no route."
  def png_data_url(png) when is_binary(png), do: "data:image/png;base64," <> Base.encode64(png)
end
