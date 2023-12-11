defmodule App.Model.Coordinate do
  def build(%{"lat" => lat, "lng" => lng}), do: build(lat, lng)
  def build(nil, _lng), do: nil
  def build(_lat, nil), do: nil
  def build(lat, lng), do: {Float.round(lat, 5), Float.round(lng, 5)}

  def to_string(nil, _precision), do: nil

  def to_string({lat, lng}, precision) do
    "#{format_value(lat, precision)},#{format_value(lng, precision)}"
  end

  defp format_value(value, precision) do
    value
    |> Decimal.from_float()
    |> Decimal.round(precision)
    |> to_string()
  end
end
