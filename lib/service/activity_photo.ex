defmodule Service.ActivityPhoto do
  @moduledoc """
  A photo on its way from a phone to an activity (#1032). `check/1` says whether a file
  that just uploaded is a photo SAR Duty can read. `prepare/1` makes the three files an
  activity photo keeps, each a JPEG with no location or camera data: the original at its
  full size, a copy up to 2048 px to show, and one up to 600 px for tiles.

  A phone's photo is read the way every photo is (Service.Image): HEIC too, where the
  server can, turned the way the camera held it. Nothing here keeps a file:
  App.Operation.AddActivityPhotos does.

  Edit photo (part 8): `plan/2`, pure, turns a team admin's settings into what is done
  to the original, and `edit/3` does it and makes the copies again. The original is
  never changed.
  """

  @max_bytes 25_000_000
  @max_photos 20
  @max_caption 300
  @show_side 2048
  @tile_side 600
  @max_angle 10
  @angle_step 0.5

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

  @doc "The most Straighten turns a photo, either way, in degrees."
  def max_angle, do: @max_angle

  @doc "Straighten's step, in degrees."
  def angle_step, do: @angle_step

  @doc """
  Pure. Settings from anywhere, made safe: `turns`, quarter turns clockwise, from 0 to
  3; `angle`, degrees clockwise, from −10 to 10 in steps of 0.5; and `clean_up`.
  """
  def settings(%{turns: turns, angle: angle, clean_up: clean_up}) do
    angle = (angle / @angle_step) |> round() |> Kernel.*(@angle_step) |> max(-@max_angle)

    %{
      turns: Integer.mod(turns, 4),
      angle: min(angle, @max_angle) / 1,
      clean_up: clean_up == true
    }
  end

  @doc "Pure. A photo's `{width, height}` once turned `turns` quarter turns."
  def turned_size(turns, {width, height}) when rem(turns, 2) == 0, do: {width, height}
  def turned_size(_turns, {width, height}), do: {height, width}

  @doc """
  Pure. How much of a photo's width and height is left when it is turned `angle`
  degrees and cut at the same shape just enough to leave no empty corners: 1 for no
  angle. The cut's corners must stay inside the turned photo, which bounds it on both
  of the photo's sides; the tighter bound wins.
  """
  def cut_scale(angle, {width, height}) do
    radians = abs(angle) * :math.pi() / 180
    {cos, sin} = {:math.cos(radians), :math.sin(radians)}
    min(width / (width * cos + height * sin), height / (width * sin + height * cos))
  end

  @doc """
  Pure. What is done to an original of `{width, height}` for `settings`, in order: the
  quarter turns, `{:turn, turns}`; then the angle with the cut that leaves no corners,
  `{:straighten, angle, {width, height}}`, the cut's size in whole pixels, centred;
  then `:clean_up`. A step with nothing to do is left out, so no edit is `[]`.
  """
  def plan(settings, {width, height}) do
    %{turns: turns, angle: angle, clean_up: clean_up} = settings(settings)
    {turned_width, turned_height} = turned_size(turns, {width, height})
    scale = cut_scale(angle, {turned_width, turned_height})

    Enum.concat([
      if(turns > 0, do: [{:turn, turns}], else: []),
      if(angle != 0,
        do: [{:straighten, angle, {floor(turned_width * scale), floor(turned_height * scale)}}],
        else: []
      ),
      if(clean_up, do: [:clean_up], else: [])
    ])
  end

  @doc """
  Does `steps`, from plan/2, to `original`, the photo's original JPEG, and makes the
  copies an activity photo shows: `{:ok, %{show:, tile:, cleaned?:}}`. `clean_up` is a
  function that takes the copy to show and answers `{:ok, jpeg}` or an error; it runs
  only for `:clean_up`, and when it fails the copies are made without it, with
  `cleaned?` false. No step is the copies as they came.
  """
  def edit(original, steps, clean_up) when is_binary(original) and is_function(clean_up, 1) do
    with {:ok, image} <- Image.from_binary(original),
         {:ok, edited} <- shape(image, steps),
         {:ok, show} <- show(edited) do
      {show, cleaned?} = cleaned(show, :clean_up in steps, clean_up)

      with {:ok, tile} <- Service.Image.jpeg(show, @tile_side),
           do: {:ok, %{show: show, tile: tile, cleaned?: cleaned?}}
    end
  end

  defp show(image) do
    with {:ok, fitted} <- Image.thumbnail(image, @show_side, resize: :down),
         do: Image.write(fitted, :memory, suffix: ".jpg", quality: 85, strip_metadata: true)
  end

  defp shape(image, steps) do
    Enum.reduce_while(steps, {:ok, image}, fn step, {:ok, image} ->
      case shape_step(image, step) do
        {:ok, image} -> {:cont, {:ok, image}}
        error -> {:halt, error}
      end
    end)
  end

  defp shape_step(image, {:turn, turns}), do: Image.rotate(image, turns * 90)

  # libvips turns it clockwise onto a larger canvas; the cut is its middle.
  defp shape_step(image, {:straighten, angle, {width, height}}) do
    with {:ok, turned} <- Image.rotate(image, angle) do
      left = div(Image.width(turned) - width, 2)
      top = div(Image.height(turned) - height, 2)
      Image.crop(turned, left, top, width, height)
    end
  end

  defp shape_step(image, :clean_up), do: {:ok, image}

  defp cleaned(show, false, _clean_up), do: {show, false}

  defp cleaned(show, true, clean_up) do
    # What comes back is read again, so it is a JPEG of the size to show, with no metadata.
    with {:ok, cleaned} when is_binary(cleaned) <- clean_up.(show),
         {:ok, jpeg} <- Service.Image.jpeg(cleaned, @show_side) do
      {jpeg, true}
    else
      _did_not_answer -> {show, false}
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
