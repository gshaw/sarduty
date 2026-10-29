defmodule Web.Components.OpenInMaps do
  @moduledoc """
  A link that opens a place in the account's maps app: Google Maps, or Apple Maps when
  they chose it on the Account page (#301). See /styles/open-in-maps.

  The link goes to the latitude and longitude when there are some, since they pin the
  exact spot, and searches for the address otherwise. Google's links cannot label a pin;
  Apple's take the label. Never label a member's address with their name: the link
  would tell Google or Apple who lives there.
  """
  use Phoenix.Component

  import Web.Components.A, only: [a: 1]

  attr :id, :string, required: true
  attr :app, :string, default: "google", doc: "the account's maps_app"
  attr :coordinate, :string, default: nil, doc: "latitude and longitude, as \"49.6,-123.2\""
  attr :address, :string, default: nil
  attr :label, :string, default: nil, doc: "Apple Maps' pin label for the coordinate"
  attr :class, :any, default: nil

  def open_in_maps(assigns) do
    assigns =
      assign(assigns, :url, url(assigns.app, assigns.coordinate, assigns.address, assigns.label))

    ~H"""
    <p :if={@url} class={["action mb-0", @class]}>
      <.a id={@id} href={@url} external icon="map-pin">Open in {app_name(@app)}</.a>
    </p>
    """
  end

  def app_name("apple"), do: "Apple Maps"
  def app_name(_google), do: "Google Maps"

  @doc """
  The app's link for a latitude and longitude, or an address when there are none. Nil
  when there is neither.
  """
  def url(app, coordinate, address, label) do
    cond do
      coordinate = blank_to_nil(coordinate) -> coordinate_url(app, coordinate, label)
      address = one_line(address) -> address_url(app, address)
      true -> nil
    end
  end

  defp coordinate_url("apple", coordinate, label),
    do: "https://maps.apple.com/?" <> URI.encode_query(ll: coordinate, q: label || coordinate)

  defp coordinate_url(_google, coordinate, _label), do: google(coordinate)

  defp address_url("apple", address),
    do: "https://maps.apple.com/?" <> URI.encode_query(q: address)

  defp address_url(_google, address), do: google(address)

  defp google(query),
    do: "https://www.google.com/maps/search/?" <> URI.encode_query(api: 1, query: query)

  @doc "A mailing address on several lines, as one line a map or a GPS app can search for."
  def one_line(nil), do: nil

  def one_line(text) do
    text |> String.split(~r/\s*\n\s*/, trim: true) |> Enum.join(", ") |> blank_to_nil()
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(text), do: if(String.trim(text) == "", do: nil, else: String.trim(text))
end
