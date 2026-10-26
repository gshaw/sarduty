defmodule App.Operation.FindPlace do
  @moduledoc """
  Finds an activity's place as a team admin types it (#610): places from Mapbox's Search
  Box, nearest the team first, and the text and coordinate of the one they pick. Only
  reads. A Mapbox failure lists nothing, so the field still takes what was typed.
  """

  alias App.Adapter.Mapbox
  alias App.Model.Team

  @doc "A new search session's token. One session is typing that ends in one pick."
  def new_session, do: Ecto.UUID.generate()

  @doc "Up to 5 places matching `text`, or none for short text or a Mapbox failure."
  def suggest(%Team{} = team, text, session_token) do
    text = String.trim(text || "")

    with true <- String.length(text) >= 3,
         {:ok, places} <-
           Mapbox.suggest_places(Mapbox.build_context(), text, session_token, near(team)) do
      Enum.reject(places, &is_nil(&1.id))
    else
      _short_or_failed -> []
    end
  end

  @doc "`{:ok, %{place: text, coordinate: {lat, lng}}}` for a pick, or `:error`."
  def pick(id, session_token) do
    case Mapbox.retrieve_place(Mapbox.build_context(), id, session_token) do
      {:ok, %{coordinate: {_lat, _lng} = coordinate} = place} ->
        {:ok, %{place: place_text(place), coordinate: coordinate}}

      _failed ->
        :error
    end
  end

  defp near(%Team{lat: lat, lng: lng}) when is_number(lat) and is_number(lng), do: {lat, lng}
  defp near(_team), do: nil

  @doc """
  The text for the form's place: the name, then the address without the country, at
  most 100 characters, as D4H takes. An address's name is its first line, so it isn't
  said twice.
  """
  def place_text(%{name: name, address: address, country: country}) do
    [name | String.split(address || "", ", ")]
    |> Enum.reject(&(&1 in [nil, "", country]))
    |> Enum.uniq()
    |> Enum.join(", ")
    |> String.slice(0, 100)
  end
end
