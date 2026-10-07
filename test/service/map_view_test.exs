defmodule Service.MapViewTest do
  use ExUnit.Case, async: true

  alias Service.MapView

  test "no points, no view" do
    assert MapView.fit([], 400, 300) == nil
  end

  test "one point sits in the middle at the zoom cap" do
    view = MapView.fit([{49.7016, -123.1558}], 400, 300, max_zoom: 11.0)

    assert view.zoom == 11.0
    assert view.positions == [{200.0, 150.0}]
    assert {lat, lng} = view.center
    assert_in_delta lat, 49.7016, 0.0001
    assert_in_delta lng, -123.1558, 0.0001
  end

  test "every point lands inside the padding" do
    points = [{49.56, -123.25}, {49.93, -123.03}, {49.70, -123.16}]
    view = MapView.fit(points, 400, 300, padding: 20)

    for {x, y} <- view.positions do
      assert x >= 19.9 and x <= 380.1
      assert y >= 19.9 and y <= 280.1
    end

    # North is up: the most northern point has the smallest y.
    [{_, south_y}, {_, north_y}, _] = view.positions
    assert north_y < south_y
  end
end
