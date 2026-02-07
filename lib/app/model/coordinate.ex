defmodule App.Model.Coordinate do
  def build(nil), do: nil

  def build(value) when is_binary(value) do
    case String.split(value, ",") do
      [lat, lng] -> build(lat, lng)
      _other -> nil
    end
  end

  def build(_value), do: nil

  def build(nil, _lng), do: nil
  def build(_lat, nil), do: nil

  def build(lat, lng) when is_binary(lat) and is_binary(lng) do
    with {lat_f, _} <- Float.parse(lat),
         {lng_f, _} <- Float.parse(lng) do
      build(lat_f, lng_f)
    else
      _error -> nil
    end
  end

  def build(lat, lng) when is_float(lat) and is_float(lng) do
    {Float.round(lat, 5), Float.round(lng, 5)}
  end

  def build(lat, lng) when is_integer(lat) and is_integer(lng) do
    # https://programming-idioms.org/idiom/79/convert-integer-to-floating-point-number/901/elixir
    {lat / 1, lng / 1}
  end

  def build(lat, lng) when is_number(lat) and is_number(lng) do
    build(lat / 1, lng / 1)
  end

  def build(_lat, _lng), do: nil

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
