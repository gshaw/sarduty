defmodule App.Adapter.Mapbox do
  def build_context(%{mapbox_access_token: access_token}) do
    Req.new(
      base_url: "https://api.mapbox.com/",
      headers: %{"User-Agent" => "sarduty.com"},
      params: [access_token: access_token]
    )
  end

  def build_context do
    build_context(%{mapbox_access_token: access_token()})
  end

  defp access_token, do: Application.get_env(:sarduty, App.Adapter.Mapbox)[:access_token]

  @doc """
  A static map with no pins, centred on `{lat, lng}` at `zoom`, `width` by `height` pixels
  at 2x. `style` is a Mapbox style such as "outdoors-v12" or "dark-v11". Nil without a
  token, or with the "dummy" token tests run with, so the page draws its points on a
  plain background instead.
  """
  def build_static_view_url(context, style, {lat, lng}, zoom, {width, height}) do
    base_url = context.options.base_url
    token = context.options.params[:access_token]

    if token in [nil, "", "dummy"] do
      nil
    else
      "#{base_url}styles/v1/mapbox/#{style}/static/#{lng},#{lat},#{zoom},0/#{width}x#{height}@2x?access_token=#{token}"
    end
  end

  def fetch_coordinate(context, address), do: fetch_coordinate(context, address, nil)

  def fetch_coordinate(context, address, {lat, lng} = _proximity) do
    fetch_coordinate(context, address, "#{lng},#{lat}")
  end

  def fetch_coordinate(context, address, proximity) do
    address =
      (address || "")
      |> String.replace("#", "%23")
      |> String.replace("\n", " ")
      |> String.replace("\r", " ")

    url = "geocoding/v5/mapbox.places/#{URI.encode(address)}.json"

    params = [
      proximity: proximity
      # types: "address"
    ]

    response = Req.get!(context, url: url, params: params)

    if response.status == 200 do
      try do
        %{"features" => [%{"center" => [lng, lat]} | _]} = response.body
        {:ok, {lat, lng}}
      rescue
        _ in MatchError -> {:error, "unknown", response}
      end
    else
      {:error, "Unknown (#{response.status})", response}
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
