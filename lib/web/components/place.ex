defmodule Web.Components.Place do
  @moduledoc """
  A place's address box (#610, #614): the text, a list of places that match it (the team's
  own, named by its saved places, then Mapbox's), and the pin of the one picked or the
  latitude and longitude pasted, on a map. This is the markup; Web.Components.PlaceBox
  runs it in a form. See /styles/place.

  Element ids start with `id`: `<id>-places`, `<id>-past-<i>`, `<id>-place-<i>`,
  `<id>-place-clear`, `<id>-pin`, and `<id>-pin-remove`.
  """
  use Phoenix.Component

  import Web.Components.ActivityMap, only: [activity_map: 1]
  import Web.Components.Core

  alias App.Model.Coordinate
  alias Phoenix.LiveView.JS
  alias Service.Format
  alias Web.Components.ActivityMap

  attr :id, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true, doc: "the address text"
  attr :coordinate, Phoenix.HTML.FormField, required: true, doc: "the pin, \"lat,lng\""
  attr :label, :string, default: "Address (optional)"
  attr :past, :list, default: [], doc: "the team's places that match, FindPlace.match_past/2"
  attr :places, :list, default: [], doc: "Mapbox's places that match"
  attr :kind, :atom, default: :event, doc: "the map dot's colour: :incident, :exercise, :event"
  attr :timezone, :string, required: true
  attr :bookmark_source, :string, required: true, doc: "where a named place's name comes from"
  attr :target, :any, default: nil, doc: "the PlaceBox that takes the list's events"

  def place_field(assigns) do
    pin = Coordinate.build(assigns.coordinate.value)

    assigns =
      assign(assigns,
        errors:
          if(used_input?(assigns.field),
            do: Enum.map(assigns.field.errors, &translate_error/1),
            else: []
          ),
        pin: pin,
        open?: assigns.past != [] or assigns.places != [],
        map: pin && place_map(pin, assigns.kind, assigns.field.value)
      )

    ~H"""
    <div class={["mb-6", @errors != [] && "field-error"]}>
      <.label for={@field.id}>{@label}</.label>
      <.hint>
        Pick a place your team has used, or type an address or a place name, like Victoria Park, Truro, and pick a match. Or paste a latitude and longitude.
      </.hint>
      <.error :for={msg <- @errors}>{msg}</.error>
      <%!-- On the box and its list, so the click that focuses the box keeps the list open. --%>
      <div
        class="place-field"
        phx-click-away={@open? && "close_places"}
        phx-window-keydown={@open? && "close_places"}
        phx-key="Escape"
        phx-target={@target}
      >
        <div class="place-input">
          <input
            type="text"
            name={@field.name}
            id={@field.id}
            value={@field.value}
            class={@errors != [] && "is-invalid"}
            autocomplete="off"
            placeholder=" "
            phx-debounce="300"
            phx-focus="show_past"
            phx-target={@target}
            aria-controls={"#{@id}-places"}
            aria-expanded={to_string(@open?)}
          />
          <button
            type="button"
            id={"#{@id}-place-clear"}
            class="place-clear"
            aria-label="Clear the address"
            phx-click={
              JS.dispatch("sarduty:clear", to: "##{@field.id}", detail: %{also: "##{@coordinate.id}"})
            }
          >
            <.icon name="x" />
          </button>
        </div>
        <ul :if={@open?} id={"#{@id}-places"} class="place-list" aria-label="Places that match">
          <li :for={{place, i} <- Enum.with_index(@past)}>
            <button
              type="button"
              id={"#{@id}-past-#{i}"}
              phx-click="pick_past"
              phx-value-i={i}
              phx-target={@target}
            >
              <span class="place-name">{place.name || place.text}</span>
              <span :if={place.name} class="place-detail">{named_detail(place, @bookmark_source)}</span>
              <span :if={place.count > 0} class="place-detail">
                {Format.count(place.count, one: "1 activity", many: "%d activities")}, last {Format.date_long(
                  place.last_at,
                  @timezone
                )}
              </span>
            </button>
          </li>
          <li :for={{place, i} <- Enum.with_index(@places)}>
            <button
              type="button"
              id={"#{@id}-place-#{i}"}
              phx-click="pick_place"
              phx-value-id={place.id}
              phx-target={@target}
              phx-disable-with="Placing the pin…"
            >
              <span class="place-name">{place.name}</span>
              <span :if={place.detail} class="place-detail">{place.detail}</span>
            </button>
          </li>
        </ul>
      </div>
      <input
        type="hidden"
        name={@coordinate.name}
        id={@coordinate.id}
        value={@coordinate.value}
      />
      <div :if={@pin} id={"#{@id}-pin"} class="mt-3">
        <.activity_map id={"#{@id}-pin-map"} map={@map} label="Map of the place" />
        <p class="hint mt-2">
          Latitude and longitude {Format.coordinate(@pin, 5)}.
          <.button
            id={"#{@id}-pin-remove"}
            type="button"
            variant={:link}
            phx-click="remove_pin"
            phx-target={@target}
          >
            Remove pin
          </.button>
        </p>
      </div>
    </div>
    """
  end

  # A bookmark with no address fills the box with its name, so it isn't said twice.
  defp named_detail(%{text: name, name: name}, source), do: source
  defp named_detail(%{text: text}, source), do: "#{text} · #{source}"

  # Close enough to see the spot among the roads and trails around it.
  defp place_map({lat, lng}, kind, place) do
    point = %{lat: lat, lng: lng, kind: kind, recent: true, tip: place}
    ActivityMap.build([point], {640, 320}, max_zoom: 14.0)
  end
end
