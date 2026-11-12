defmodule Service.CertificateFile do
  @moduledoc """
  A member's certificate file (#493), ready to keep: a PDF as it came, or a photo
  re-encoded as a JPEG up to 2000 px with its metadata gone (GPS, camera). The type
  comes from the file's first bytes, never its name.
  """

  @max_bytes 10_000_000
  @max_side 2000

  @doc "The largest file a member can send."
  def max_bytes, do: @max_bytes

  @doc """
  `{:ok, %{bytes:, content_type:, file_name:}}`, or `{:error, text}` saying what to send
  instead.
  """
  def prepare(bytes, file_name) when is_binary(bytes) do
    if byte_size(bytes) > @max_bytes,
      do: {:error, "Select a file under #{Service.Format.file_size(@max_bytes)}."},
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
        {:error, "SAR Duty cannot read this photo. Select another photo or a PDF."}
    end
  end

  defp prepare(:unknown, _bytes, _file_name), do: {:error, "Select a photo or a PDF."}

  @doc """
  A kept photo turned a quarter, `:left` or `:right`, for one the camera held sideways.
  `{:ok, jpeg}`, or `{:error, reason}`.
  """
  def rotate(jpeg, direction) when direction in [:left, :right] do
    with {:ok, image} <- Image.from_binary(jpeg),
         {:ok, turned} <- Image.rotate(image, if(direction == :right, do: 90, else: -90)) do
      Image.write(turned, :memory, suffix: ".jpg", quality: 85, strip_metadata: true)
    end
  end

  @doc "What the file is, from its first bytes: `:pdf`, `:image`, `:heic`, or `:unknown`."
  def type(<<"%PDF-", _rest::binary>>), do: :pdf
  def type(bytes), do: Service.Image.kind(bytes)

  # A photo is read the way every photo a phone sends is (Service.Image.jpeg/2).
  defp to_jpeg(bytes), do: Service.Image.jpeg(bytes, @max_side)

  defp jpeg_name(file_name) do
    case Path.rootname(file_name || "") do
      "" -> "Certificate.jpg"
      root -> root <> ".jpg"
    end
  end
end
