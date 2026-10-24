defmodule Service.CertificateFile do
  @moduledoc """
  A member's certificate file (#493), ready to keep: a PDF as it came, or a photo
  re-encoded as a JPEG up to 2000 px with its metadata gone (GPS, camera). The type
  comes from the file's first bytes, never its name.
  """

  @max_bytes 10_000_000
  @max_side 2000
  # The most pixels a photo can claim. A real photo under 10 MB has at most about 108
  # million (12000 × 9000, from a 108 MP phone camera). A PNG of a few hundred bytes can
  # claim 40000 × 40000, 1,600 million, which would take minutes and gigabytes to decode.
  @max_pixels 120_000_000

  @doc "The largest file a member can send."
  def max_bytes, do: @max_bytes

  @doc """
  `{:ok, %{bytes:, content_type:, file_name:}}`, or `{:error, text}` saying what to send
  instead.
  """
  def prepare(bytes, file_name) when is_binary(bytes) do
    if byte_size(bytes) > @max_bytes,
      do: {:error, "Choose a file under #{Service.Format.file_size(@max_bytes)}."},
      else: prepare(type(bytes), bytes, file_name)
  end

  defp prepare(:pdf, bytes, file_name),
    do: {:ok, %{bytes: bytes, content_type: "application/pdf", file_name: file_name}}

  defp prepare(kind, bytes, file_name) when kind in [:image, :heic] do
    case to_jpeg(bytes) do
      {:ok, jpeg} ->
        {:ok, %{bytes: jpeg, content_type: "image/jpeg", file_name: jpeg_name(file_name)}}

      {:error, :too_many_pixels} ->
        {:error, "SAR Duty cannot read a photo this large. Select a smaller photo or a PDF."}

      {:error, _reason} when kind == :heic ->
        {:error, "SAR Duty cannot read this photo. Send it as a JPEG."}

      {:error, _reason} ->
        {:error, "SAR Duty cannot read this photo. Choose another photo or a PDF."}
    end
  end

  defp prepare(:unknown, _bytes, _file_name), do: {:error, "Choose a photo or a PDF."}

  @doc "What the file is, from its first bytes: `:pdf`, `:image`, `:heic`, or `:unknown`."
  def type(<<"%PDF-", _rest::binary>>), do: :pdf
  def type(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: :image
  def type(<<0x89, "PNG", _rest::binary>>), do: :image
  def type(<<"GIF8", _rest::binary>>), do: :image
  # cspell:ignore webp -- the WebP image type's signature
  def type(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: :image

  # cspell:ignore ftyp heic heix hevc hevx heim heis -- HEIF file brands
  def type(<<_size::binary-size(4), "ftyp", brand::binary-size(4), _rest::binary>>)
      when brand in ["heic", "heix", "hevc", "hevx", "mif1", "msf1", "heim", "heis"],
      do: :heic

  def type(_bytes), do: :unknown

  # Turned the way the camera held it, flattened onto white, and saved without metadata.
  # Opening reads only the header, so the size is checked before anything is decoded.
  defp to_jpeg(bytes) do
    with {:ok, image} <- Image.from_binary(bytes),
         :ok <- check_pixels(image),
         {:ok, fitted} <- Image.thumbnail(image, @max_side, resize: :down, autorotate: true),
         {:ok, flat} <- flatten(fitted) do
      Image.write(flat, :memory, suffix: ".jpg", quality: 85, strip_metadata: true)
    end
  end

  defp check_pixels(image) do
    if Image.width(image) * Image.height(image) > @max_pixels,
      do: {:error, :too_many_pixels},
      else: :ok
  end

  defp flatten(image) do
    if Image.has_alpha?(image),
      do: Image.flatten(image, background: :white),
      else: {:ok, image}
  end

  defp jpeg_name(file_name) do
    case Path.rootname(file_name || "") do
      "" -> "Certificate.jpg"
      root -> root <> ".jpg"
    end
  end
end
