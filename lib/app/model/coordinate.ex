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

  @doc """
  Puts the pin in a form's changeset from its `:place` and `:coordinate` (#610): a pasted
  latitude and longitude is the pin, otherwise the one picked, kept as "lat,lng" to 5
  places, or none. Shared by every form with a place box.
  """
  def put_pin(%Ecto.Changeset{} = changeset) do
    pasted = changeset |> Ecto.Changeset.get_field(:place) |> parse()
    pin = pasted || changeset |> Ecto.Changeset.get_field(:coordinate) |> build()
    Ecto.Changeset.put_change(changeset, :coordinate, pin && to_string(pin, 5))
  end

  @doc """
  The `{lat, lng}` in text a person pasted, or nil when it isn't one (#610). Takes
  decimals ("49.01732, -122.65634"), hemispheres ("49.0173 N 122.6563 W"), degrees and
  minutes, degrees, minutes, and seconds (49°01'02.4"N 122°39'22.8"W), and a Google or
  Apple Maps link with the decimals in it.
  """
  def parse(text) when is_binary(text) do
    if text =~ ~r/https?:/i, do: parse_link(text), else: parse_text(text)
  end

  def parse(_text), do: nil

  # The first decimal pair in the link: Google's /@lat,lng,zoom or ?q=, Apple's ?ll=.
  defp parse_link(text) do
    case Regex.run(~r/(-?\d{1,2}\.\d+)\s*(?:,|%2C)\s*(-?\d{1,3}\.\d+)/i, text) do
      [_match, lat, lng] -> checked({String.to_float(lat), String.to_float(lng)})
      nil -> nil
    end
  end

  # cspell:ignore NSEW -- the four hemisphere letters, as a regex class
  # Degrees, then minutes and seconds if given.
  @numbers ~S"(-?\d+(?:\.\d+)?)(?:\s+(\d+(?:\.\d+)?))?(?:\s+(\d+(?:\.\d+)?))?"
  # "N 49 01.04 W 122 39.38", or "49 01.04 N 122 39.38 W" and "49.0173, -122.6563".
  @leading Regex.compile!("^([NSEW])\\s*#{@numbers}\\s*,?\\s*([NSEW])\\s*#{@numbers}$")
  @trailing Regex.compile!("^#{@numbers}\\s*([NSEW]?)\\s*(?:,|\\s)\\s*#{@numbers}\\s*([NSEW]?)$")

  defp parse_text(text) do
    text = text |> String.upcase() |> String.replace(~r/[°º'"′″’”]/u, " ") |> String.trim()

    with [a, b] <- halves(text),
         # Plain whole numbers, like "12 34", are not a coordinate.
         true <- Enum.any?([a, b], &precise?/1),
         {:ok, a_degrees} <- degrees(a),
         {:ok, b_degrees} <- degrees(b) do
      oriented({a.hemisphere, a_degrees}, {b.hemisphere, b_degrees})
    else
      _not_a_coordinate -> nil
    end
  end

  # Latitude first, unless the hemispheres say longitude came first.
  defp oriented({h, a}, {k, b}) when h in ["", "N", "S"] and k in ["", "E", "W"],
    do: checked({a, b})

  defp oriented({h, a}, {k, b}) when h in ["E", "W"] and k in ["N", "S"], do: checked({b, a})
  defp oriented(_a, _b), do: nil

  # Each half's hemisphere and numbers. Regex.run leaves off groups at the end that
  # matched nothing, so they are put back as "".
  defp halves(text) do
    cond do
      groups = Regex.run(@leading, text, capture: :all_but_first) ->
        [h, d, m, s, k, e, n, t] = pad(groups)
        [half(h, [d, m, s]), half(k, [e, n, t])]

      groups = Regex.run(@trailing, text, capture: :all_but_first) ->
        [d, m, s, h, e, n, t, k] = pad(groups)
        [half(h, [d, m, s]), half(k, [e, n, t])]

      true ->
        nil
    end
  end

  defp pad(groups), do: groups ++ List.duplicate("", 8 - length(groups))

  defp half(hemisphere, numbers),
    do: %{hemisphere: hemisphere, numbers: Enum.reject(numbers, &(&1 == ""))}

  defp precise?(%{hemisphere: h, numbers: numbers}),
    do: h != "" or length(numbers) > 1 or Enum.any?(numbers, &(&1 =~ "."))

  # Signed by its hemisphere or a minus. Minutes and seconds are under 60.
  defp degrees(%{hemisphere: hemisphere, numbers: numbers}) do
    [degrees, minutes, seconds] =
      numbers |> Enum.map(&to_number/1) |> Enum.concat([0, 0]) |> Enum.take(3)

    sign = if degrees < 0 or hemisphere in ["S", "W"], do: -1, else: 1

    if minutes < 60 and seconds < 60,
      do: {:ok, sign * (abs(degrees) + minutes / 60 + seconds / 3600)},
      else: :error
  end

  defp to_number(text) do
    {number, ""} = Float.parse(text)
    number
  end

  defp checked({lat, lng}) when abs(lat) <= 90 and abs(lng) <= 180, do: build(lat, lng)
  defp checked(_coordinate), do: nil

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
