defmodule Service.Image do
  @moduledoc """
  Shapes member photos and team logos for passes and /verify. Wallet has no CSS, so the
  server does what `object-cover` does on the site. Every function takes image bytes in
  any format libvips reads and returns `{:ok, png}` or `{:error, reason}`.
  """

  @doc "Crops a photo to the centered square at its shorter side, no larger than `max`."
  def square(bytes, max \\ 660) do
    with {:ok, image} <- Image.from_binary(bytes),
         side = min(min(Image.width(image), Image.height(image)), max),
         {:ok, square} <- Image.thumbnail(image, side, crop: :center) do
      to_png(square)
    end
  end

  @doc "Converts to PNG, scaled down to fit `max` on its longer side."
  def png(bytes, max) do
    with {:ok, image} <- Image.from_binary(bytes),
         {:ok, fitted} <- Image.thumbnail(image, max, resize: :down) do
      to_png(fitted)
    end
  end

  @doc """
  Fits a logo inside a square of `side`, padded with `background`, so nothing is cut
  off. `margin` is the share of the side left clear on each edge, so a round frame
  doesn't clip the corners.
  """
  def pad_square(bytes, side, opts \\ []) do
    background = Keyword.get(opts, :background, :white)
    margin = Keyword.get(opts, :margin, 0.0)
    inner = round(side * (1 - 2 * margin))

    with {:ok, image} <- Image.from_binary(bytes),
         {:ok, fitted} <- Image.thumbnail(image, inner),
         {:ok, flat} <- flatten(fitted, background),
         {:ok, padded} <- Image.embed(flat, side, side, background: background) do
      to_png(padded)
    end
  end

  @doc """
  The photo cropped square at the banner's height and centered in a `width` × `height`
  banner of `background`. Google stretches a hero image to the card's width.
  """
  def banner(bytes, width, height, background) do
    with {:ok, image} <- Image.from_binary(bytes),
         {:ok, square} <- Image.thumbnail(image, height, crop: :center),
         {:ok, flat} <- flatten(square, background),
         {:ok, wide} <- Image.embed(flat, width, height, background: background) do
      to_png(wide)
    end
  end

  defp flatten(image, background) do
    if Image.has_alpha?(image),
      do: Image.flatten(image, background: background),
      else: {:ok, image}
  end

  defp to_png(image), do: Image.write(image, :memory, suffix: ".png")
end
