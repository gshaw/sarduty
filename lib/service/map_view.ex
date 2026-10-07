defmodule Service.MapView do
  @moduledoc """
  Fits points on a Web Mercator map of a fixed size, as Mapbox's static images draw it.

  `fit/4` picks the centre and zoom that show every point, and gives each point its pixel
  position on the image. The dashboard draws the points itself on top of a plain static
  map, so the dots follow the design system instead of Mapbox's pins.
  """

  # Mapbox static images use 512px tiles: the whole world is 512px wide at zoom 0.
  @tile 512
  @max_zoom 12.0

  @doc """
  The view of `width` by `height` pixels that holds every `{lat, lng}` in `points`.

  Returns `%{center: {lat, lng}, zoom: zoom, positions: [{x, y}]}`, with one position per
  point, in order. `:padding` keeps points that far from the edge, and `:max_zoom` stops one
  point, or points close together, from zooming in to street level.
  """
  def fit(points, width, height, opts \\ [])

  def fit([], _width, _height, _opts), do: nil

  def fit(points, width, height, opts) do
    padding = Keyword.get(opts, :padding, 32)
    world = Enum.map(points, &to_world/1)
    {center, spans} = bounds(world)
    zoom = zoom_to_fit(spans, {width - 2 * padding, height - 2 * padding}, opts)
    positions = Enum.map(world, &to_pixels(&1, center, zoom, {width, height}))
    %{center: to_lat_lng(center), zoom: zoom, positions: positions}
  end

  @doc "The distance between two `{lat, lng}` in km, on a 6,371 km Earth."
  def km_between({lat1, lng1}, {lat2, lng2}) do
    cos1 = lat1 |> radians() |> :math.cos()
    cos2 = lat2 |> radians() |> :math.cos()
    half_chord = haversine(lat2 - lat1) + cos1 * cos2 * haversine(lng2 - lng1)

    2 * 6371 * (half_chord |> :math.sqrt() |> :math.asin())
  end

  defp haversine(degrees), do: (radians(degrees) / 2) |> :math.sin() |> :math.pow(2)
  defp radians(degrees), do: degrees * :math.pi() / 180

  # The middle of the points in world pixels, and how far they spread across and down.
  defp bounds(world) do
    {xs, ys} = Enum.unzip(world)
    {min_x, max_x} = Enum.min_max(xs)
    {min_y, max_y} = Enum.min_max(ys)
    {{(min_x + max_x) / 2, (min_y + max_y) / 2}, {max_x - min_x, max_y - min_y}}
  end

  defp zoom_to_fit({span_x, span_y}, {room_x, room_y}, opts) do
    [zoom_for(span_x, room_x), zoom_for(span_y, room_y), Keyword.get(opts, :max_zoom, @max_zoom)]
    |> Enum.min()
    |> Float.floor(2)
  end

  defp to_pixels({x, y}, {center_x, center_y}, zoom, {width, height}) do
    scale = :math.pow(2, zoom)
    {round_px((x - center_x) * scale + width / 2), round_px((y - center_y) * scale + height / 2)}
  end

  defp zoom_for(span, _pixels) when span <= 0, do: @max_zoom
  defp zoom_for(span, pixels), do: :math.log2(max(pixels, 1) / span)

  defp to_world({lat, lng}) do
    phi = radians(lat)
    x = (lng + 180) / 360 * @tile
    y = (1 - :math.log(:math.tan(phi) + 1 / :math.cos(phi)) / :math.pi()) / 2 * @tile
    {x, y}
  end

  defp to_lat_lng({x, y}) do
    lng = x / @tile * 360 - 180
    lat = (:math.pi() * (1 - 2 * y / @tile)) |> :math.sinh() |> :math.atan() |> degrees()
    {Float.round(lat, 5), Float.round(lng, 5)}
  end

  defp degrees(radians), do: radians * 180 / :math.pi()

  defp round_px(value), do: Float.round(value, 1)
end
