defmodule Web.Components.TravelChoices do
  @moduledoc """
  How someone got to an activity (#230), as radios: drove to the ICP or the yard with the
  round trip from home, a passenger at 0 km, Other with a km box, and Not set where it
  can be cleared. One set of choices for Your travel (Web.Components.TravelCheck) and the
  Travel tab's Change dialog (Web.Components.TravelTab), so they read the same.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [hint: 1]

  alias App.ViewData.ActivityTravel
  alias Phoenix.LiveView.JS
  alias Service.Format

  attr :id, :string, required: true, doc: "names Other's radio, which its km box picks"
  attr :legend, :string, required: true
  attr :hint, :string, required: true
  attr :class, :string, default: nil

  attr :routes, :map,
    default: nil,
    doc: "one row's `activity_km` and `yard_km`, nil for none; nil for several rows: no km"

  attr :current, :string, default: nil, doc: ~s(the saved travel, "clear" for none)
  attr :km, :integer, default: nil, doc: "Other's saved km"
  attr :clear?, :boolean, default: false, doc: "offers Not set"

  def travel_choices(assigns) do
    ~H"""
    <fieldset class={@class}>
      <legend>{@legend}</legend>
      <.hint>{@hint}</.hint>
      <label :for={{travel, km} <- ways(@routes)} class="choice">
        <input
          type="radio"
          name="travel"
          value={travel}
          checked={@current == travel}
          disabled={no_route?(@routes, km, @current, travel)}
        />
        <span>{way_text(travel, @routes, km)}</span>
      </label>
      <label class="choice">
        <input type="radio" name="travel" value="passenger" checked={@current == "passenger"} />
        <span>Passenger, {Format.km(0)}</span>
      </label>
      <label class="choice travel-other-choice">
        <input
          type="radio"
          id={"#{@id}-other"}
          name="travel"
          value="other"
          checked={@current == "other"}
        />
        <%!-- The km box on Other's own line; typing in it picks Other. --%>
        <span class="inline-flex items-center gap-2">
          Other
          <input
            type="number"
            phx-focus={JS.dispatch("click", to: "##{@id}-other")}
            name="km"
            min="0"
            step="1"
            inputmode="numeric"
            value={if @current == "other", do: @km}
            class="w-16"
            aria-label="km round trip"
          /> km round trip
        </span>
      </label>
      <label :if={@clear?} class="choice">
        <input type="radio" name="travel" value="clear" checked={@current == "clear"} />
        <span>Not set</span>
      </label>
    </fieldset>
    """
  end

  defp ways(nil), do: [{"icp", nil}, {"yard", nil}]
  defp ways(routes), do: [{"icp", routes.activity_km}, {"yard", routes.yard_km}]

  # A way with no route can't be picked for one row, unless it's what's saved.
  defp no_route?(nil, _km, _current, _travel), do: false
  defp no_route?(_routes, km, current, travel), do: is_nil(km) and current != travel

  # "Drove to the ICP, 86 km" for one row; "Drove to the ICP" for several.
  defp way_text(travel, nil, _km), do: ActivityTravel.travel_text(travel)

  defp way_text(travel, _routes, km),
    do: "#{ActivityTravel.travel_text(travel)}, #{if km, do: Format.km(km), else: "no route"}"
end
