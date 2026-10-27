defmodule Web.Components.PlaceBox do
  @moduledoc """
  Runs Web.Components.Place in any form that takes a place or a pin (#614), so they all
  work alike: the team's own places on focus, then Mapbox's as the person types, a pasted
  latitude and longitude, and Remove pin. It keeps the search; the form keeps the values.

  The form does two things. Its phx-change passes a change to the address on:

      PlaceBox.typed(id, params["place"])

  and it takes a pick, or Remove pin, as the values to put in the form and validate:

      def handle_info({PlaceBox, %{"place" => _, "coordinate" => _} = values}, socket)

  The team's past places are read once, when the box mounts.
  """
  use Web, :live_component

  alias App.Adapter.D4H
  alias App.Model.Coordinate
  alias App.Operation.FindPlace
  alias Web.Components.Place

  @doc "Tells the box `id` the address now reads `text`, so it lists what matches."
  def typed(id, text), do: send_update(__MODULE__, id: id, typed: text)

  def mount(socket),
    do: {:ok, assign(socket, past: [], places: [], session: FindPlace.new_session())}

  def update(%{typed: text}, socket), do: {:ok, find_places(socket, text)}

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if Map.has_key?(socket.assigns, :past_places),
        do: socket,
        else: assign(socket, past_places: FindPlace.past_places(assigns.team, DateTime.utc_now()))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id={"#{@id}-box"}>
      <Place.place_field
        id={@id}
        field={@field}
        coordinate={@coordinate}
        label={@label}
        past={@past}
        places={@places}
        kind={@kind}
        timezone={@team.timezone}
        bookmark_source={bookmark_source(@team)}
        target={@myself}
      />
    </div>
    """
  end

  # Where a named place's name comes from, and so where to change it.
  defp bookmark_source(team),
    do: if(D4H.records?(team), do: "Saved place", else: "#{D4H.service_name(team)} bookmark")

  # The team's own places, with no Mapbox call, so the usual ones are a tap away.
  def handle_event("show_past", _params, socket) do
    %{past_places: past_places, field: field} = socket.assigns
    {:noreply, assign(socket, past: FindPlace.match_past(past_places, field.value))}
  end

  def handle_event("pick_past", %{"i" => i}, socket) do
    %{past: past} = socket.assigns

    case Integer.parse(i) do
      {i, ""} when i in 0..(length(past) - 1)//1 ->
        place = Enum.at(past, i)

        {:noreply,
         picked(socket, %{"place" => place.text, "coordinate" => place.coordinate || ""})}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("pick_place", %{"id" => id}, socket) do
    session = socket.assigns.session

    case FindPlace.pick(id, session) do
      {:ok, %{place: place, coordinate: coordinate}} ->
        values = %{"place" => place, "coordinate" => Coordinate.to_string(coordinate, 5)}
        {:noreply, picked(socket, values)}

      :error ->
        socket
        |> assign(past: [], places: [], session: FindPlace.new_session())
        |> put_flash(:error, "Mapbox did not answer. Pick the place again.")
        |> then(&{:noreply, &1})
    end
  end

  # A pasted latitude and longitude is the pin, so it goes too.
  def handle_event("remove_pin", _params, socket) do
    text = socket.assigns.field.value
    place = if Coordinate.parse(text), do: "", else: text
    {:noreply, picked(socket, %{"place" => place, "coordinate" => ""})}
  end

  def handle_event("close_places", _params, socket),
    do: {:noreply, assign(socket, past: [], places: [])}

  def handle_async(:places, {:ok, places}, socket), do: {:noreply, assign(socket, places: places)}
  def handle_async(:places, {:exit, _reason}, socket), do: {:noreply, assign(socket, places: [])}

  # The form puts the values in and validates. A pick ends the Mapbox session.
  defp picked(socket, values) do
    send(self(), {__MODULE__, values})
    assign(socket, past: [], places: [], session: FindPlace.new_session())
  end

  # Places that match the text, unless it is a latitude and longitude: the team's own at
  # once, and Mapbox's from 3 characters. The latest search wins when one is still running.
  defp find_places(socket, text) do
    %{team: team, session: session, past_places: past_places} = socket.assigns

    cond do
      Coordinate.parse(text) ->
        socket |> cancel_async(:places) |> assign(past: [], places: [])

      short?(text) ->
        socket
        |> cancel_async(:places)
        |> assign(past: FindPlace.match_past(past_places, text), places: [])

      true ->
        socket
        |> assign(past: FindPlace.match_past(past_places, text))
        |> start_async(:places, fn -> FindPlace.suggest(team, text, session) end)
    end
  end

  defp short?(nil), do: true
  defp short?(text), do: text |> String.trim() |> String.length() < 3
end
