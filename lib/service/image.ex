defmodule Service.Image do
  @moduledoc """
  Shapes member photos and team logos for passes and /verify. Wallet has no CSS, so the
  server does what `object-cover` does on the site. Each shape takes image bytes in any
  format libvips reads and returns `{:ok, png}` or `{:error, reason}`.

  It also reads a photo a phone sent, for a certificate (#493) or a member's photo
  (#1028): `kind/1` says what the bytes are, and `jpeg/2` makes the clean JPEG.
  """

  # The most pixels a photo can claim. A real photo under 10 MB has at most about 108
  # million (12000 × 9000, from a 108 MP phone camera). A PNG of a few hundred bytes can
  # claim 40000 × 40000, 1,600 million, which would take minutes and gigabytes to decode.
  @max_pixels 120_000_000

  @doc "What a photo's bytes are, from the first of them: `:image`, `:heic`, or `:unknown`."
  def kind(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: :image
  def kind(<<0x89, "PNG", _rest::binary>>), do: :image
  def kind(<<"GIF8", _rest::binary>>), do: :image
  # cspell:ignore webp -- the WebP image type's signature
  def kind(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: :image

  # cspell:ignore ftyp heic heix hevc hevx heim heis -- HEIF file brands
  def kind(<<_size::binary-size(4), "ftyp", brand::binary-size(4), _rest::binary>>)
      when brand in ["heic", "heix", "hevc", "hevx", "mif1", "msf1", "heim", "heis"],
      do: :heic

  def kind(_bytes), do: :unknown

  @doc """
  A photo as a JPEG no larger than `max` on its longer side: turned the way the camera
  held it, flattened onto white, and saved without metadata (GPS, camera). `{:ok, jpeg}`,
  `{:error, :too_many_pixels}`, or `{:error, reason}`.
  """
  # Opening reads only the header, so the size is checked before anything is decoded.
  def jpeg(bytes, max) do
    with {:ok, image} <- Image.from_binary(bytes),
         :ok <- check_pixels(image),
         {:ok, fitted} <- Image.thumbnail(image, max, resize: :down, autorotate: true),
         {:ok, flat} <- flatten(fitted, :white) do
      Image.write(flat, :memory, suffix: ".jpg", quality: 85, strip_metadata: true)
    end
  end

  @doc """
  A photo as a JPEG at its full size, for the copy SAR Duty keeps as the original
  (#1032): turned the way the camera held it, flattened onto white, and saved without
  metadata (GPS, camera), like `jpeg/2`. `{:ok, jpeg}`, `{:error, :too_many_pixels}`,
  or `{:error, reason}`.
  """
  def full_jpeg(bytes) do
    with {:ok, image} <- Image.from_binary(bytes),
         :ok <- check_pixels(image),
         {:ok, {turned, _flags}} <- Image.autorotate(image),
         {:ok, flat} <- flatten(turned, :white) do
      Image.write(flat, :memory, suffix: ".jpg", quality: 92, strip_metadata: true)
    end
  end

  @doc """
  Whether a photo's bytes open as one `jpeg/2` would take, from the header alone, with
  nothing decoded: `:ok`, `{:error, :too_many_pixels}`, or `{:error, reason}`.
  """
  def check(bytes) do
    with {:ok, image} <- Image.from_binary(bytes), do: check_pixels(image)
  end

  defp check_pixels(image) do
    if Image.width(image) * Image.height(image) > @max_pixels,
      do: {:error, :too_many_pixels},
      else: :ok
  end

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
  Fits a logo inside a transparent square of `side`, so nothing is cut off and it sits
  on any background. Google fills the transparency with white in its circle. `margin` is
  the share of the side left clear on each edge, so a round frame doesn't clip the
  corners.
  """
  def pad_square(bytes, side, opts \\ []) do
    margin = Keyword.get(opts, :margin, 0.0)
    inner = round(side * (1 - 2 * margin))

    with {:ok, image} <- Image.from_binary(bytes),
         {:ok, fitted} <- Image.thumbnail(image, inner),
         {:ok, alpha} <- with_alpha(fitted),
         {:ok, padded} <- Image.embed(alpha, side, side, background: :transparent) do
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

  defp with_alpha(image) do
    if Image.has_alpha?(image), do: {:ok, image}, else: Image.add_alpha(image, :opaque)
  end

  defp to_png(image), do: Image.write(image, :memory, suffix: ".png")
end
