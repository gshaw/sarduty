defmodule App.Model.Coordinate do
  def build(value) do
    [lat, lng] = String.split(value, ",")
    build(lat, lng)
  end

  def build(nil, _lng), do: nil
  def build(_lat, nil), do: nil

  def build(lat, lng) when is_binary(lat) and is_binary(lng) do
    build(String.to_float(lat), String.to_float(lng))
  end

  def build(lat, lng) when is_float(lat) and is_float(lng) do
    {Float.round(lat, 5), Float.round(lng, 5)}
  end

  def build(lat, lng) when is_integer(lat) and is_integer(lng) do
    # https://programming-idioms.org/idiom/79/convert-integer-to-floating-point-number/901/elixir
    {lat / 1, lng / 1}
  end

  def build_mapbox({lat, lng}), do: "#{lng},#{lat}"

  def to_string({lat, lng}, precision) do
    "#{format_value(lat, precision)},#{format_value(lng, precision)}"
  end

  def to_string(value, _precision), do: value

  defp format_value(value, precision) do
    value
    |> Decimal.from_float()
    |> Decimal.round(precision)
    |> to_string()
  end
end
