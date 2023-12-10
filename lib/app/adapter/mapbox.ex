defmodule App.Adapter.Mapbox do
  # alias App.Adapter.Mapbox

  def build_context(%{mapbox_access_key: access_key}) do
    Req.new(
      base_url: "https://api.mapbox.com/",
      headers: %{"User-Agent" => "sarduty.com"},
      params: [access_token: access_key]
    )
  end

  def build_context() do
    build_context(%{
      mapbox_access_key:
        "pk.eyJ1IjoiZ3NoYXciLCJhIjoiY2xwcDcwZXRiMHduNzJxbzlrZnM2b2d0NiJ9.LDPtgWSj-dAs8zkw3w99Pw"
    })
  end

  def fetch_coordinate(context, address), do: fetch_coordinate(context, address, nil)

  def fetch_coordinate(context, address, {lat, lng} = _proximity) do
    fetch_coordinate(context, address, "#{lng},#{lat}")
  end

  def fetch_coordinate(context, address, proximity) do
    url = "geocoding/v5/mapbox.places/#{URI.encode(address)}.json"

    params = [
      proximity: proximity,
      types: "address"
    ]

    response = Req.get!(context, url: url, params: params)

    if response.status == 200 do
      try do
        %{"features" => [%{"center" => [lng, lat]} | _]} = response.body
        {:ok, {lat, lng}}
      rescue
        _ in MatchError -> {:error, "Unable to geocode `#{address}`"}
      end
    else
      {:error, response}
    end
  end

  def fetch_driving_info(context, {from_lat, from_lng}, {to_lat, to_lng}) do
    url = "directions/v5/mapbox/driving/#{from_lng},#{from_lat};#{to_lng},#{to_lat}"
    response = Req.get!(context, url: url, params: [language: "en"])

    if response.status == 200 do
      %{"routes" => [%{"distance" => distance, "duration" => duration} | _]} = response.body
      {:ok, distance, duration}
    else
      {:error, response}
    end
  end

  def fetch_driving_info(context) do
    fetch_driving_info(context, {49.265271, -123.17205}, {49.19159, -122.72672})
  end
end
