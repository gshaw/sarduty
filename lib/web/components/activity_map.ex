defmodule Web.Components.ActivityMap do
  @moduledoc """
  A map of activities: a plain Mapbox static image, outdoors in light mode and dark in dark
  mode, with a dot per activity drawn on top in SVG. The dots take the kind's colour from
  the tokens, so they match the badges and charts. Without a Mapbox token the dots sit on a
  plain panel, which still shows where things happen.
  """
  use Phoenix.Component

  alias App.Adapter.Mapbox
  alias Web.MapImage

  @doc """
  Builds the map for `points`, each `%{lat: 49.7, lng: -123.1, kind: :incident, tip:
  "…"}`, at `width` by `height`. Nil when no point has a place.
  """
  def build(points, {width, height} = size, opts \\ []) do
    view =
      points
      |> Enum.map(&{&1.lat, &1.lng})
      |> Service.MapView.fit(width, height, opts)

    case view do
      nil ->
        nil

      view ->
        %{
          width: width,
          height: height,
          light_url: image_url("outdoors-v12", view, size),
          dark_url: image_url("dark-v11", view, size),
          dots:
            points
            |> Enum.zip(view.positions)
            |> Enum.map(fn {point, {x, y}} -> Map.merge(point, %{x: x, y: y}) end)
        }
    end
  end

  defp image_url(style, view, size) do
    style |> Mapbox.static_view_path(view.center, view.zoom, size) |> MapImage.url()
  end

  @doc "Draws a map from `build/3`. The inner block sits over the map's top left corner."
  attr :id, :string, required: true
  attr :map, :map, required: true
  attr :label, :string, required: true
  attr :overlay, :boolean, default: true, doc: "false when the caller passes an empty slot on"
  slot :inner_block

  def activity_map(assigns) do
    ~H"""
    <figure
      id={@id}
      class="chart-map"
      style={"margin: 0; aspect-ratio: #{@map.width} / #{@map.height}"}
      aria-label={@label}
    >
      <img :if={@map.light_url} class="is-light" src={@map.light_url} alt="" loading="lazy" />
      <img :if={@map.dark_url} class="is-dark" src={@map.dark_url} alt="" loading="lazy" />
      <svg viewBox={"0 0 #{@map.width} #{@map.height}"} aria-hidden="true">
        <circle
          :for={dot <- Enum.sort_by(@map.dots, &kind_order(&1.kind))}
          class={["series-#{dot.kind}", dot[:recent] && "is-recent"]}
          cx={dot.x}
          cy={dot.y}
          r="5"
        >
          <title>{dot.tip}</title>
        </circle>
      </svg>
      <div
        :if={@overlay and @inner_block != []}
        class="chart-map-overlay"
        style="top: 12px; left: 12px"
      >
        {render_slot(@inner_block)}
      </div>
    </figure>
    """
  end

  # Incidents are drawn last, so they sit on top where dots overlap.
  defp kind_order(:incident), do: 2
  defp kind_order(:exercise), do: 1
  defp kind_order(_kind), do: 0
end
