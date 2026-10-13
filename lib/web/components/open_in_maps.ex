defmodule Web.Components.OpenInMaps do
  @moduledoc """
  Open in Google Maps, as a split button whose menu switches to Apple Maps or copies the
  place for a GPS app (#301). The MapPick hook (assets/js/map_pick.js) remembers the
  app picked on this device. See /styles/open-in-maps.

  The link goes to the latitude and longitude when there are some, since they pin the
  exact spot, and searches for the address otherwise. Google's links cannot label a pin;
  Apple's take the label. Never label a member's address with their name: the link
  would tell Google or Apple who lives there.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [button: 1, icon: 1]

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :coordinate, :string, default: nil, doc: "latitude and longitude, as \"49.6,-123.2\""
  attr :address, :string, default: nil
  attr :label, :string, default: nil, doc: "Apple Maps' pin label for the coordinate"
  attr :class, :any, default: nil

  def open_in_maps(assigns) do
    assigns = assign(assigns, :urls, urls(assigns.coordinate, assigns.address, assigns.label))
    assigns = assign(assigns, :hide_menu, hide_menu(assigns.id))

    ~H"""
    <div
      :if={@urls}
      id={@id}
      class={["open-in-maps", @class]}
      phx-hook="MapPick"
      phx-click-away={@hide_menu}
    >
      <span class="btn-split">
        <.button
          size={:sm}
          href={@urls.google}
          target="_blank"
          data-map-open
          data-google={@urls.google}
          data-apple={@urls.apple}
        >
          Open in <span data-map-name>Google Maps</span>
          <.icon name="hero-arrow-top-right-on-square-micro" />
        </.button>
        <.button
          id={"#{@id}-more"}
          type="button"
          size={:sm}
          aria-label="Choose a maps app, or copy"
          aria-haspopup="menu"
          aria-expanded="false"
          aria-controls={"#{@id}-menu"}
          phx-click={
            JS.toggle(to: "##{@id}-menu")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
        >
          <.icon name="hero-chevron-down-micro" />
        </.button>
      </span>
      <div id={"#{@id}-menu"} class="menu menu-start hidden" role="menu">
        <a
          :for={{app, name} <- [google: "Google Maps", apple: "Apple Maps"]}
          id={"#{@id}-#{app}"}
          href={@urls[app]}
          target="_blank"
          role="menuitemradio"
          aria-checked={to_string(app == :google)}
          data-map-pick={app}
          phx-click={@hide_menu}
        >
          {name} <.icon name="hero-check-circle-micro" class="menu-check" />
        </a>
        <hr />
        <button
          :for={{what, text} <- copies(@coordinate, @address)}
          id={"#{@id}-copy-#{what}"}
          type="button"
          role="menuitem"
          value={text}
          phx-click={JS.dispatch(@hide_menu, "sarduty:copy", detail: %{status: "##{@id}-copied"})}
        >
          Copy {if what == :coordinate, do: "latitude and longitude", else: "address"}
        </button>
        <p class="menu-note">SAR Duty remembers your maps app on this device.</p>
      </div>
      <span id={"#{@id}-copied"} class="open-in-maps-copied" aria-live="polite"></span>
    </div>
    """
  end

  defp hide_menu(id) do
    JS.hide(to: "##{id}-menu")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id}-more")
  end

  @doc """
  Google's and Apple's links for a latitude and longitude, or an address when there are
  none. Nil when there is neither.
  """
  def urls(coordinate, address, label) do
    cond do
      coordinate = blank_to_nil(coordinate) ->
        %{
          google: google(coordinate),
          apple:
            "https://maps.apple.com/?" <> URI.encode_query(ll: coordinate, q: label || coordinate)
        }

      address = address |> one_line() |> blank_to_nil() ->
        %{
          google: google(address),
          apple: "https://maps.apple.com/?" <> URI.encode_query(q: address)
        }

      true ->
        nil
    end
  end

  defp google(query),
    do: "https://www.google.com/maps/search/?" <> URI.encode_query(api: 1, query: query)

  defp copies(coordinate, address) do
    [coordinate: blank_to_nil(coordinate), address: address |> one_line() |> blank_to_nil()]
    |> Enum.reject(fn {_what, text} -> is_nil(text) end)
  end

  # A mailing address on several lines, as one line a map can search for.
  defp one_line(nil), do: nil

  defp one_line(text),
    do: text |> String.split(~r/\s*\n\s*/, trim: true) |> Enum.join(", ")

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(text), do: if(String.trim(text) == "", do: nil, else: String.trim(text))
end
