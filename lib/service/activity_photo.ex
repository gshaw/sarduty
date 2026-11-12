defmodule Service.ActivityPhoto do
  @moduledoc """
  A photo on its way from a phone to an activity (#1032). `check/1` says whether a file
  that just uploaded is a photo SAR Duty can read. `prepare/1` makes the three files an
  activity photo keeps, each a JPEG with no location or camera data: the original at its
  full size, a copy up to 2048 px to show, and one up to 600 px for tiles.

  A phone's photo is read the way every photo is (Service.Image): HEIC too, where the
  server can, turned the way the camera held it. Nothing here keeps a file:
  App.Operation.AddActivityPhotos does.
  """

  @max_bytes 25_000_000
  @max_photos 20
  @max_caption 300
  @show_side 2048
  @tile_side 600

  @doc "The largest photo Add photos takes."
  def max_bytes, do: @max_bytes

  @doc "The most photos in one send."
  def max_photos, do: @max_photos

  @doc "The longest caption, in characters."
  def max_caption, do: @max_caption

  @doc """
  Whether `bytes` is a photo SAR Duty can read, from its header, with nothing decoded:
  `:ok`, or `{:error, text}` saying what to do instead.
  """
  def check(bytes) when is_binary(bytes) do
    kind = Service.Image.kind(bytes)

    with :ok <- check_size(bytes),
         :ok <- check_kind(kind),
         :ok <- Service.Image.check(bytes) do
      :ok
    else
      error -> {:error, error_text(kind, error)}
    end
  end

  @doc """
  What an activity photo keeps of `bytes`: `{:ok, %{original:, show:, tile:, width:,
  height:}}`, three JPEGs and the original's size, or `{:error, text}`.
  """
  def prepare(bytes) when is_binary(bytes) do
    kind = Service.Image.kind(bytes)

    with :ok <- check_size(bytes),
         :ok <- check_kind(kind),
         {:ok, files} <- files(bytes) do
      {:ok, files}
    else
      error -> {:error, error_text(kind, error)}
    end
  end

  # The three files, and the original's size once it is turned.
  defp files(bytes) do
    with {:ok, original} <- Service.Image.full_jpeg(bytes),
         {:ok, show} <- Service.Image.jpeg(bytes, @show_side),
         {:ok, tile} <- Service.Image.jpeg(bytes, @tile_side),
         {:ok, image} <- Image.from_binary(original) do
      size = %{width: Image.width(image), height: Image.height(image)}
      {:ok, Map.merge(size, %{original: original, show: show, tile: tile})}
    end
  end

  defp check_size(bytes),
    do: if(byte_size(bytes) > @max_bytes, do: {:error, :too_large}, else: :ok)

  defp check_kind(kind) when kind in [:image, :heic], do: :ok
  defp check_kind(_kind), do: {:error, :not_a_photo}

  # What to do instead. The image library's own words never reach the page.
  defp error_text(_kind, {:error, :too_large}),
    do: "Select photos under #{Service.Format.file_size(@max_bytes)} each."

  defp error_text(_kind, {:error, :not_a_photo}),
    do: "Select photos. SAR Duty cannot read this file."

  defp error_text(_kind, {:error, :too_many_pixels}),
    do: "SAR Duty cannot read a photo this large. Select a smaller photo."

  defp error_text(:heic, _error), do: "SAR Duty cannot read this photo. Select a JPEG."
  defp error_text(_kind, _error), do: "SAR Duty cannot read this photo. Select another."
end
