defmodule App.Model.Coordinate do
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
