defmodule Service.PhotoExport do
  @moduledoc """
  Export for a post (#1032, part 9): a copy of an activity photo in the shape a post
  needs. `shapes/0` are the shapes, `crop/3`, pure, turns a shape, where the box was
  placed, and the photo's size into the crop and the size it downloads at, and
  `export/3` cuts it out as a JPEG with no metadata.

  The box is placed with the same hook as a member's photo (assets/js/photo_place.js),
  and sent the same way: `x` and `y`, its centre as shares of the photo's width and
  height, and `side`, as a share of the largest box of that shape the photo holds.
  Service.MemberPhoto.placement/1 reads them.
  """

  alias Service.MemberPhoto

  # Each shape: its key, as the page sends it, what people read, the size it downloads
  # at, and where it is used. Original keeps the photo's own shape and size.
  @shapes [
    %{key: "square", label: "Square 1:1", size: {1080, 1080}, used_for: "Instagram, Facebook"},
    %{key: "portrait", label: "Portrait 4:5", size: {1080, 1350}, used_for: "Instagram feed"},
    %{
      key: "landscape",
      label: "Landscape 16:9",
      size: {1920, 1080},
      used_for: "Facebook, website, YouTube"
    },
    %{
      key: "story",
      label: "Story 9:16",
      size: {1080, 1920},
      used_for: "Instagram and Facebook stories"
    },
    %{key: "original", label: "Original", size: nil, used_for: "Anywhere"}
  ]

  @doc "The shapes a photo exports in, the first the one a page starts on."
  def shapes, do: @shapes

  @doc "The shape with `key`, or the first for a key that is not one."
  def shape(key), do: Enum.find(@shapes, hd(@shapes), &(&1.key == key))

  @doc """
  Pure. The box's shape, width over height, for a photo of `{width, height}`: the
  shape's own, or the photo's for Original.
  """
  def ratio(%{size: nil}, {width, height}), do: width / height
  def ratio(%{size: {width, height}}, _photo), do: width / height

  @doc """
  Pure. The crop an export asks for, in the photo's pixels, and the size it downloads
  at. `shape` is one of `shapes/0`, `box` is `%{x:, y:, side:}` as placed, and `size`
  is the photo's `{width, height}` as edited.

  The box keeps the shape's ratio, stays inside the photo, and is never under a fifth
  of the largest box the photo holds. It downloads at the shape's size, or smaller when
  the box has fewer pixels: never enlarged. Original downloads at the box's own size.
  `%{left:, top:, width:, height:, out_width:, out_height:}`.
  """
  def crop(shape, %{x: x, y: y, side: side}, {width, height})
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    ratio = ratio(shape, {width, height})
    {box_width, box_height} = box_size(side, ratio, {width, height})
    {out_width, out_height} = out_size(shape, {box_width, box_height}, ratio)

    %{
      left: corner(x, width, box_width),
      top: corner(y, height, box_height),
      width: box_width,
      height: box_height,
      out_width: out_width,
      out_height: out_height
    }
  end

  # The largest box of the shape the photo holds, then the share of it placed.
  defp box_size(side, ratio, {width, height}) do
    max_width = if width / height > ratio, do: height * ratio, else: width
    share = clamp(side, MemberPhoto.min_share(), 1.0)
    box_width = (share * max_width) |> round() |> max(1) |> min(width)
    {box_width, (box_width / ratio) |> round() |> max(1) |> min(height)}
  end

  defp out_size(%{size: nil}, box, _ratio), do: box

  defp out_size(%{size: {width, height}}, {box_width, box_height}, ratio) do
    if box_width >= width,
      do: {width, height},
      else: {box_width, (box_width / ratio) |> round() |> max(1) |> min(box_height)}
  end

  # The box's near edge, from its centre as a share of `length`, kept inside.
  defp corner(centre, length, box) do
    (clamp(centre, 0.0, 1.0) * length - box / 2)
    |> round()
    |> max(0)
    |> min(length - box)
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  @doc """
  The export of `image`, the photo as edited, a `Vix.Vips.Image`: cut to `shape` and
  `box` (crop/3) and sized to download, as a JPEG with no location or camera data.
  `{:ok, jpeg}` or `{:error, reason}`.
  """
  def export(%Vix.Vips.Image{} = image, shape, box) do
    crop = crop(shape, box, {Image.width(image), Image.height(image)})

    with {:ok, cut} <- Image.crop(image, crop.left, crop.top, crop.width, crop.height),
         {:ok, sized} <- size(cut, crop) do
      Image.write(sized, :memory, suffix: ".jpg", quality: 90, strip_metadata: true)
    end
  end

  # The cut keeps the shape to within a pixel, so forcing the exact size bends nothing.
  defp size(cut, %{width: width, height: height, out_width: width, out_height: height}),
    do: {:ok, cut}

  defp size(cut, %{out_width: width, out_height: height}),
    do: Image.thumbnail(cut, width, height: height, resize: :force)
end
