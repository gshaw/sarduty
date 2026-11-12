defmodule Service.MemberPhoto do
  @moduledoc """
  A member's photo on its way from a phone to the team's records (#1028), in three steps.
  `prepare/1` reads what the phone sent, HEIC included, the way a certificate's photo is
  read (Service.Image.jpeg/2), into the copy Add a photo shows for placing. `crop/3` turns where the person
  placed it into pixels. `place/3` cuts that square out and saves it as the JPEG that
  goes to the team's records, up to 1024 × 1024 with no metadata.

  Nothing here keeps a photo: Add a photo holds the copy in its own page until it saves.
  """

  @max_bytes 10_000_000
  # The copy that is placed, on its longer side, and the photo that is saved.
  @working_side 2000
  @side 1024
  # The closest zoom: the square is never under a fifth of the photo's shorter side.
  @min_share 0.2

  @doc "The largest photo Add a photo takes."
  def max_bytes, do: @max_bytes

  @doc "The closest zoom, as the square's share of the photo's shorter side."
  def min_share, do: @min_share

  @doc """
  The photo as Add a photo shows it for placing: a JPEG up to 2000 px, turned the way the
  camera held it, with its size. `{:ok, %{bytes:, width:, height:}}`, or `{:error, text}`
  saying what to do instead.
  """
  def prepare(bytes) when is_binary(bytes) do
    if byte_size(bytes) > @max_bytes,
      do: {:error, "Select a photo under #{Service.Format.file_size(@max_bytes)}."},
      else: prepare(Service.Image.kind(bytes), bytes)
  end

  defp prepare(kind, bytes) when kind in [:image, :heic] do
    with {:ok, jpeg} <- Service.Image.jpeg(bytes, @working_side),
         {:ok, image} <- Image.from_binary(jpeg) do
      {:ok, %{bytes: jpeg, width: Image.width(image), height: Image.height(image)}}
    else
      {:error, :too_many_pixels} ->
        {:error, "SAR Duty cannot read a photo this large. Select a smaller photo."}

      {:error, _reason} when kind == :heic ->
        {:error, "SAR Duty cannot read this photo. Select a JPEG."}

      {:error, _reason} ->
        {:error, "SAR Duty cannot read this photo. Take another, or select one."}
    end
  end

  defp prepare(_kind, _bytes), do: {:error, "Select a photo. SAR Duty cannot read this file."}

  @doc """
  Where the person placed the photo, from Add a photo's hidden fields: `turns`, quarter
  turns clockwise, and the square the ID card shows, in the turned photo: `x` and `y`,
  its centre as shares of the width and height, and `side`, as a share of the shorter
  side. A field that is missing or not a number takes the middle square, unturned.
  `{turns, %{x:, y:, side:}}`.
  """
  def placement(params) when is_map(params) do
    turns =
      case params["turns"] |> to_string() |> Integer.parse() do
        {turns, ""} -> turns
        _other -> 0
      end

    {turns,
     %{
       x: share(params["x"], 0.5),
       y: share(params["y"], 0.5),
       side: share(params["side"], 1.0)
     }}
  end

  defp share(text, default) do
    case text |> to_string() |> Float.parse() do
      {share, ""} -> share
      _other -> default
    end
  end

  @doc """
  Pure. The crop a placed photo asks for: `size` is the photo's `{width, height}`,
  `turns` the quarter turns clockwise, and `placed` the square as `placement/1` reads it.
  `%{turns: 0..3, left:, top:, side:}`, in the turned photo's pixels. The square stays
  inside the photo, and is never under a fifth of its shorter side, whatever was sent.
  """
  def crop({width, height}, turns, %{x: x, y: y, side: side})
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 and
             is_integer(turns) do
    turns = Integer.mod(turns, 4)
    {width, height} = if rem(turns, 2) == 1, do: {height, width}, else: {width, height}
    shorter = min(width, height)

    side = round(clamp(side, @min_share, 1.0) * shorter)
    side = side |> max(1) |> min(shorter)

    %{
      turns: turns,
      left: corner(x, width, side),
      top: corner(y, height, side),
      side: side
    }
  end

  # The square's near edge, from its centre as a share of `length`, kept inside.
  defp corner(centre, length, side) do
    (clamp(centre, 0.0, 1.0) * length - side / 2)
    |> round()
    |> max(0)
    |> min(length - side)
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  @doc """
  The photo that is saved: `jpeg`, the copy from `prepare/1`, turned, cut to the placed
  square, and shrunk to fit 1024 × 1024, as a JPEG with no metadata. A square under
  1024 px stays its size: enlarging adds nothing. `{:ok, jpeg}` or `{:error, reason}`.
  """
  def place(jpeg, turns, placed) when is_binary(jpeg) do
    with {:ok, image} <- Image.from_binary(jpeg),
         crop = crop({Image.width(image), Image.height(image)}, turns, placed),
         {:ok, turned} <- turn(image, crop.turns),
         {:ok, square} <- Image.crop(turned, crop.left, crop.top, crop.side, crop.side),
         {:ok, fitted} <- Image.thumbnail(square, @side, resize: :down) do
      Image.write(fitted, :memory, suffix: ".jpg", quality: 85, strip_metadata: true)
    end
  end

  defp turn(image, 0), do: {:ok, image}
  defp turn(image, turns), do: Image.rotate(image, turns * 90)
end
