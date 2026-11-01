defmodule App.Adapter.Mapbox do
  alias App.Model.Coordinate

  def build_context(%{mapbox_access_token: access_token}) do
    Req.new(
      base_url: "https://api.mapbox.com/",
      headers: %{"User-Agent" => "sarduty.com"},
      params: [access_token: access_token]
    )
    |> Req.merge(Keyword.take(config(), [:plug]))
  end

  def build_context do
    build_context(%{mapbox_access_token: access_token()})
  end

  defp access_token, do: config()[:access_token]

  defp config, do: Application.get_env(:sarduty, __MODULE__, [])

  @doc """
  The path of a static map with no pins, centred on `{lat, lng}` at `zoom`, `width` by
  `height` pixels at 2x. `style` is a Mapbox style such as "outdoors-v12" or "dark-v11".
  Pages show it through `Web.MapImage`, so the token never reaches a browser. Nil without
  a token, or with the "dummy" token tests run with, so the page draws its points on a
  plain background instead.
  """
  def static_view_path(style, {lat, lng}, zoom, {width, height}) do
    if access_token() in [nil, "", "dummy"] do
      nil
    else
      "styles/v1/mapbox/#{style}/static/#{lng},#{lat},#{zoom},0/#{width}x#{height}@2x"
    end
  end

  @doc "Fetches the image at a path from `static_view_path/4`."
  def fetch_static_image(context, path) do
    case Req.get(context, url: path, decode_body: false, retry: false) do
      {:ok, %{status: 200} = response} ->
        {:ok,
         %{
           body: response.body,
           content_type: header(response, "content-type") || "image/png",
           cache_control: header(response, "cache-control")
         }}

      {:ok, %{status: status}} ->
        {:error, status}

      {:error, _exception} ->
        {:error, :unreachable}
    end
  end

  @doc """
  Whether Mapbox takes the token (#789): `{:ok, account}`, or `{:error, code}` with
  Mapbox's code, such as "TokenRevoked". Draws no map and counts as no use.
  """
  def check_token(context) do
    case Req.get(context, url: "tokens/v2", retry: false) do
      {:ok, %{status: 200, body: %{"code" => "TokenValid", "token" => token}}} ->
        {:ok, token["user"]}

      {:ok, %{body: %{"code" => code}}} ->
        {:error, code}

      {:ok, %{status: status}} ->
        {:error, "Mapbox answered #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp header(response, name), do: response |> Req.Response.get_header(name) |> List.first()

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

  # Search Box (#610) bills a session: suggestions while a person types, then the one they
  # pick. Calls with the same session token make one session. Categories and brands are
  # left out, since they name many places, not one.
  @place_types "poi,address,street,place,locality,neighborhood,postcode"

  @doc """
  Up to 5 places matching `text`, nearest `near` (`{lat, lng}` or nil) first:
  `{:ok, [%{id: "dXJu…", name: "Campbell Valley Regional Park", detail: "20285 8 Ave,
  Langley, V2Z 1V5, Canada"}]}`, or `{:error, reason}`.
  """
  def suggest_places(context, text, session_token, near) do
    params =
      [q: text, session_token: session_token, limit: 5, language: "en", types: @place_types] ++
        if(near, do: [proximity: build_proximity(near)], else: [])

    case Req.get(context, url: "search/searchbox/v1/suggest", params: params, retry: false) do
      {:ok, %{status: 200, body: %{"suggestions" => suggestions}}} ->
        {:ok, Enum.map(suggestions, &build_suggestion/1)}

      {:ok, %{status: status}} ->
        {:error, status}

      {:error, _exception} ->
        {:error, :unreachable}
    end
  end

  defp build_suggestion(suggestion) do
    %{
      id: suggestion["mapbox_id"],
      name: suggestion["name"],
      detail: suggestion["full_address"] || suggestion["place_formatted"]
    }
  end

  defp build_proximity({lat, lng}), do: "#{lng},#{lat}"

  @doc """
  The place a person picked from `suggest_places/4`: `{:ok, %{name: "…", address: "20285
  8 Ave, Langley, V2Z 1V5, Canada", country: "Canada", coordinate: {lat, lng}}}`.
  """
  def retrieve_place(context, id, session_token) do
    url = "search/searchbox/v1/retrieve/#{URI.encode(id, &URI.char_unreserved?/1)}"

    case Req.get(context, url: url, params: [session_token: session_token], retry: false) do
      {:ok, %{status: 200, body: %{"features" => [feature | _]}}} ->
        {:ok, build_place(feature)}

      {:ok, %{status: status}} ->
        {:error, status}

      {:error, _exception} ->
        {:error, :unreachable}
    end
  end

  defp build_place(%{"geometry" => %{"coordinates" => [lng, lat]}, "properties" => properties}) do
    %{
      name: properties["name"],
      address: properties["full_address"] || properties["place_formatted"],
      country: get_in(properties, ["context", "country", "name"]),
      coordinate: Coordinate.build(lat, lng)
    }
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
